create table if not exists public.account_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  event_type text not null check (
    event_type in (
      'account_created',
      'payment_pending',
      'payment_waiting_for_capture',
      'payment_succeeded',
      'payment_canceled',
      'subscription_activated',
      'subscription_updated',
      'translation_completed'
    )
  ),
  source_table text not null check (
    source_table in ('auth.users', 'payments', 'subscriptions', 'translation_sessions')
  ),
  source_id text not null,
  plan_id text check (plan_id is null or plan_id in ('free', 'start', 'pro')),
  amount numeric(10, 2),
  currency text check (currency is null or currency = 'RUB'),
  usage_seconds double precision check (usage_seconds is null or usage_seconds >= 0),
  occurred_at timestamptz not null,
  recorded_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists account_events_user_occurred_idx
  on public.account_events (user_id, occurred_at desc);
create index if not exists account_events_type_occurred_idx
  on public.account_events (event_type, occurred_at desc);
create index if not exists account_events_source_idx
  on public.account_events (source_table, source_id);

alter table public.account_events enable row level security;
revoke all on table public.account_events from public, anon, authenticated;
grant select on table public.account_events to service_role;

create or replace function public.audit_new_account()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.account_events (
    user_id, event_type, source_table, source_id, occurred_at
  ) values (
    new.id, 'account_created', 'auth.users', new.id::text, new.created_at
  );
  return new;
end;
$$;

drop trigger if exists audit_account_created on auth.users;
create trigger audit_account_created
  after insert on auth.users
  for each row execute function public.audit_new_account();

create or replace function public.audit_payment_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' or old.status is distinct from new.status then
    insert into public.account_events (
      user_id,
      event_type,
      source_table,
      source_id,
      plan_id,
      amount,
      currency,
      occurred_at,
      metadata
    ) values (
      new.user_id,
      ('payment_' || new.status),
      'payments',
      new.id::text,
      new.plan_id,
      new.amount,
      new.currency,
      coalesce(new.paid_at, new.updated_at, new.created_at),
      jsonb_build_object(
        'provider', new.provider,
        'provider_payment_id', new.provider_payment_id,
        'payment_method', new.payment_method,
        'test', new.test
      )
    );
  end if;
  return new;
end;
$$;

drop trigger if exists audit_payment_history on public.payments;
create trigger audit_payment_history
  after insert or update on public.payments
  for each row execute function public.audit_payment_change();

create or replace function public.audit_subscription_change()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT'
     or old.plan_id is distinct from new.plan_id
     or old.status is distinct from new.status
     or old.current_period_end is distinct from new.current_period_end then
    insert into public.account_events (
      user_id,
      event_type,
      source_table,
      source_id,
      plan_id,
      occurred_at,
      metadata
    ) values (
      new.user_id,
      case when tg_op = 'INSERT' then 'subscription_activated' else 'subscription_updated' end,
      'subscriptions',
      new.user_id::text,
      new.plan_id,
      new.updated_at,
      jsonb_build_object(
        'status', new.status,
        'current_period_start', new.current_period_start,
        'current_period_end', new.current_period_end,
        'auto_renew', new.auto_renew
      )
    );
  end if;
  return new;
end;
$$;

drop trigger if exists audit_subscription_history on public.subscriptions;
create trigger audit_subscription_history
  after insert or update on public.subscriptions
  for each row execute function public.audit_subscription_change();

create or replace function public.audit_translation_session()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.account_events (
    user_id,
    event_type,
    source_table,
    source_id,
    usage_seconds,
    occurred_at,
    metadata
  ) values (
    new.user_id,
    'translation_completed',
    'translation_sessions',
    new.id::text,
    new.duration_seconds,
    new.ended_at,
    jsonb_build_object(
      'source_name', new.source_name,
      'source_language', new.source_language,
      'target_language', new.target_language
    )
  );
  return new;
end;
$$;

drop trigger if exists audit_translation_history on public.translation_sessions;
create trigger audit_translation_history
  after insert on public.translation_sessions
  for each row execute function public.audit_translation_session();

-- Backfill the creation event for accounts that existed before this ledger.
insert into public.account_events (
  user_id, event_type, source_table, source_id, occurred_at
)
select id, 'account_created', 'auth.users', id::text, created_at
from auth.users
where not exists (
  select 1
  from public.account_events events
  where events.source_table = 'auth.users'
    and events.source_id = auth.users.id::text
    and events.event_type = 'account_created'
);

create or replace view public.admin_account_overview
with (security_invoker = true)
as
with payment_totals as (
  select
    user_id,
    count(*) as payment_count,
    count(*) filter (where status = 'succeeded') as successful_payment_count,
    coalesce(sum(amount) filter (where status = 'succeeded'), 0) as total_paid_rub,
    max(coalesce(paid_at, created_at)) as last_payment_at
  from public.payments
  group by user_id
), usage_totals as (
  select
    user_id,
    count(*) as session_count,
    coalesce(sum(duration_seconds), 0) as total_usage_seconds,
    coalesce(sum(duration_seconds) filter (
      where ended_at >= date_trunc('month', now())
    ), 0) as current_month_usage_seconds,
    max(ended_at) as last_translation_at
  from public.translation_sessions
  group by user_id
)
select
  users.id as user_id,
  users.email,
  users.created_at as account_created_at,
  users.last_sign_in_at,
  coalesce(subscriptions.plan_id, 'free') as current_plan,
  coalesce(subscriptions.status, 'active') as subscription_status,
  subscriptions.current_period_start,
  subscriptions.current_period_end,
  coalesce(payment_totals.payment_count, 0) as payment_count,
  coalesce(payment_totals.successful_payment_count, 0) as successful_payment_count,
  coalesce(payment_totals.total_paid_rub, 0) as total_paid_rub,
  payment_totals.last_payment_at,
  coalesce(usage_totals.session_count, 0) as session_count,
  coalesce(usage_totals.total_usage_seconds, 0) as total_usage_seconds,
  coalesce(usage_totals.current_month_usage_seconds, 0) as current_month_usage_seconds,
  usage_totals.last_translation_at
from auth.users users
left join public.subscriptions on subscriptions.user_id = users.id
left join payment_totals on payment_totals.user_id = users.id
left join usage_totals on usage_totals.user_id = users.id;

create or replace view public.admin_monthly_usage
with (security_invoker = true)
as
select
  sessions.user_id,
  users.email,
  date_trunc('month', sessions.ended_at) as usage_month,
  count(*) as session_count,
  sum(sessions.duration_seconds) as usage_seconds,
  min(sessions.started_at) as first_session_at,
  max(sessions.ended_at) as last_session_at
from public.translation_sessions sessions
join auth.users users on users.id = sessions.user_id
group by sessions.user_id, users.email, date_trunc('month', sessions.ended_at);

create or replace view public.admin_account_timeline
with (security_invoker = true)
as
select
  events.id,
  events.user_id,
  users.email,
  events.event_type,
  events.source_table,
  events.source_id,
  events.plan_id,
  events.amount,
  events.currency,
  events.usage_seconds,
  events.occurred_at,
  events.recorded_at,
  events.metadata
from public.account_events events
join auth.users users on users.id = events.user_id;

revoke all on public.admin_account_overview from public, anon, authenticated;
revoke all on public.admin_monthly_usage from public, anon, authenticated;
revoke all on public.admin_account_timeline from public, anon, authenticated;
grant select on public.admin_account_overview to service_role;
grant select on public.admin_monthly_usage to service_role;
grant select on public.admin_account_timeline to service_role;
