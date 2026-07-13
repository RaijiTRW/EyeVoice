alter table public.subscriptions
  add column if not exists pending_plan_id text,
  add column if not exists cancel_at_period_end boolean not null default false,
  add column if not exists payment_method_title text,
  add column if not exists card_last4 text,
  add column if not exists renewal_attempted_at timestamptz,
  add column if not exists renewal_lock_until timestamptz,
  add column if not exists renewal_error text;

alter table public.subscriptions
  drop constraint if exists subscriptions_pending_plan_id_check;

alter table public.subscriptions
  add constraint subscriptions_pending_plan_id_check
  check (pending_plan_id is null or pending_plan_id in ('free', 'start', 'pro'));

create index if not exists subscriptions_due_renewal_idx
  on public.subscriptions (current_period_end, auto_renew)
  where status = 'active';

create table if not exists public.billing_cron_config (
  singleton boolean primary key default true check (singleton),
  secret text not null default encode(gen_random_bytes(32), 'hex'),
  created_at timestamptz not null default now()
);

insert into public.billing_cron_config (singleton)
values (true)
on conflict (singleton) do nothing;

alter table public.billing_cron_config enable row level security;
revoke all on table public.billing_cron_config from anon, authenticated;
grant select on table public.billing_cron_config to service_role;

create or replace function public.claim_due_subscriptions()
returns setof public.subscriptions
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  return query
  update public.subscriptions s
  set
    renewal_attempted_at = now(),
    renewal_lock_until = now() + interval '30 minutes',
    renewal_error = null,
    updated_at = now()
  where s.user_id in (
    select due.user_id
    from public.subscriptions due
    where due.status = 'active'
      and due.auto_renew = true
      and due.provider_payment_method_id is not null
      and due.current_period_end <= now()
      and coalesce(due.pending_plan_id, due.plan_id) <> 'free'
      and (due.renewal_lock_until is null or due.renewal_lock_until < now())
    order by due.current_period_end
    limit 50
    for update skip locked
  )
  returning s.*;
end;
$$;

revoke all on function public.claim_due_subscriptions() from public, anon, authenticated;
grant execute on function public.claim_due_subscriptions() to service_role;

create or replace function public.expire_due_subscriptions()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  affected integer;
begin
  update public.subscriptions
  set
    status = 'expired',
    auto_renew = false,
    pending_plan_id = null,
    cancel_at_period_end = false,
    updated_at = now()
  where status = 'active'
    and current_period_end <= now()
    and (
      auto_renew = false
      or provider_payment_method_id is null
      or pending_plan_id = 'free'
    );
  get diagnostics affected = row_count;
  return affected;
end;
$$;

revoke all on function public.expire_due_subscriptions() from public, anon, authenticated;
grant execute on function public.expire_due_subscriptions() to service_role;

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
     or old.current_period_end is distinct from new.current_period_end
     or old.auto_renew is distinct from new.auto_renew
     or old.pending_plan_id is distinct from new.pending_plan_id
     or old.provider_payment_method_id is distinct from new.provider_payment_method_id then
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
        'auto_renew', new.auto_renew,
        'pending_plan_id', new.pending_plan_id,
        'cancel_at_period_end', new.cancel_at_period_end,
        'has_payment_method', new.provider_payment_method_id is not null,
        'card_last4', new.card_last4
      )
    );
  end if;
  return new;
end;
$$;

-- Supabase Cron invokes the renewal worker. The shared secret is generated in
-- the database and is never committed to the repository or exposed to clients.
create extension if not exists pg_cron with schema extensions;
create extension if not exists pg_net with schema extensions;

do $$
declare
  existing_job bigint;
begin
  select jobid into existing_job
  from cron.job
  where jobname = 'eyevoice-renew-subscriptions';

  if existing_job is not null then
    perform cron.unschedule(existing_job);
  end if;

  perform cron.schedule(
    'eyevoice-renew-subscriptions',
    '*/15 * * * *',
    $cron$
      select net.http_post(
        url := 'https://seexmgivktuycodxrjhs.supabase.co/functions/v1/renew-subscriptions',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'x-cron-secret', (select secret from public.billing_cron_config where singleton = true)
        ),
        body := '{}'::jsonb
      );
    $cron$
  );
end;
$$;
