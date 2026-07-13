alter table public.payments
  add column if not exists product_type text not null default 'plan'
    check (product_type in ('plan', 'extra_hours')),
  add column if not exists quantity_hours integer
    check (quantity_hours is null or quantity_hours between 1 and 100);

create table if not exists public.usage_periods (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  plan_id text not null check (plan_id in ('start', 'pro')),
  period_start timestamptz not null,
  period_end timestamptz not null,
  base_seconds bigint not null check (base_seconds >= 0),
  rollover_seconds bigint not null default 0 check (rollover_seconds >= 0),
  addon_seconds bigint not null default 0 check (addon_seconds >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint usage_period_order check (period_end > period_start),
  unique (user_id, period_start)
);

create index if not exists usage_periods_user_period_idx
  on public.usage_periods (user_id, period_start desc, period_end desc);

alter table public.usage_periods enable row level security;

drop policy if exists "Users can read their usage periods" on public.usage_periods;
create policy "Users can read their usage periods"
  on public.usage_periods for select to authenticated
  using (auth.uid() = user_id);

revoke all on table public.usage_periods from public, anon, authenticated;
grant select on table public.usage_periods to authenticated;
grant all on table public.usage_periods to service_role;

create or replace function public.activate_usage_period(
  p_user_id uuid,
  p_plan_id text,
  p_period_start timestamptz,
  p_period_end timestamptz
)
returns public.usage_periods
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  previous_period public.usage_periods%rowtype;
  result public.usage_periods%rowtype;
  used_seconds double precision := 0;
  regular_remaining bigint := 0;
  addon_remaining bigint := 0;
  carry_cap bigint;
  new_base bigint;
begin
  if p_plan_id not in ('start', 'pro') then
    raise exception 'Unsupported plan';
  end if;
  if p_period_end <= p_period_start then
    raise exception 'Invalid usage period';
  end if;

  new_base := case when p_plan_id = 'pro' then 15 * 3600 else 5 * 3600 end;
  carry_cap := new_base;

  select * into previous_period
  from public.usage_periods
  where user_id = p_user_id
    and period_start < p_period_start
  order by period_start desc
  limit 1;

  if found then
    select coalesce(sum(duration_seconds), 0)
      into used_seconds
    from public.translation_sessions
    where user_id = p_user_id
      and ended_at >= previous_period.period_start
      and ended_at < least(previous_period.period_end, p_period_start);

    regular_remaining := greatest(
      previous_period.base_seconds + previous_period.rollover_seconds - floor(used_seconds)::bigint,
      0
    );
    addon_remaining := greatest(
      previous_period.addon_seconds - greatest(
        floor(used_seconds)::bigint - previous_period.base_seconds - previous_period.rollover_seconds,
        0
      ),
      0
    );
  end if;

  insert into public.usage_periods (
    user_id,
    plan_id,
    period_start,
    period_end,
    base_seconds,
    rollover_seconds,
    addon_seconds,
    updated_at
  ) values (
    p_user_id,
    p_plan_id,
    p_period_start,
    p_period_end,
    new_base,
    least(regular_remaining, carry_cap),
    addon_remaining,
    now()
  )
  on conflict (user_id, period_start) do update set
    plan_id = excluded.plan_id,
    period_end = excluded.period_end,
    base_seconds = excluded.base_seconds,
    rollover_seconds = excluded.rollover_seconds,
    addon_seconds = greatest(public.usage_periods.addon_seconds, excluded.addon_seconds),
    updated_at = now()
  returning * into result;

  return result;
end;
$$;

create or replace function public.add_usage_hours(
  p_user_id uuid,
  p_plan_id text,
  p_hours integer
)
returns public.usage_periods
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  result public.usage_periods%rowtype;
begin
  if p_plan_id not in ('start', 'pro') or p_hours not between 1 and 100 then
    raise exception 'Invalid extra-hours purchase';
  end if;

  update public.usage_periods
  set addon_seconds = addon_seconds + p_hours * 3600,
      updated_at = now()
  where id = (
    select id
    from public.usage_periods
    where user_id = p_user_id
      and plan_id = p_plan_id
      and period_start <= now()
      and period_end > now()
    order by period_start desc
    limit 1
    for update
  )
  returning * into result;

  if not found then
    raise exception 'No active paid usage period';
  end if;

  return result;
end;
$$;


revoke all on function public.activate_usage_period(uuid, text, timestamptz, timestamptz)
  from public, anon, authenticated;
revoke all on function public.add_usage_hours(uuid, text, integer)
  from public, anon, authenticated;
grant execute on function public.activate_usage_period(uuid, text, timestamptz, timestamptz)
  to service_role;
grant execute on function public.add_usage_hours(uuid, text, integer)
  to service_role;

-- Existing active subscriptions receive a current metered period without inventing
-- historical rollover. Later periods are created through activate_usage_period().
insert into public.usage_periods (
  user_id,
  plan_id,
  period_start,
  period_end,
  base_seconds,
  rollover_seconds,
  addon_seconds
)
select
  user_id,
  plan_id,
  current_period_start,
  current_period_end,
  case when plan_id = 'pro' then 15 * 3600 else 5 * 3600 end,
  0,
  0
from public.subscriptions
where status = 'active'
  and current_period_end > now()
on conflict (user_id, period_start) do nothing;

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
        'test', new.test,
        'product_type', new.product_type,
        'quantity_hours', new.quantity_hours
      )
    );
  end if;
  return new;
end;
$$;
