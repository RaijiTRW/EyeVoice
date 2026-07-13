-- EyeVoice administration, privacy-friendly site analytics and provider costs.

create table if not exists public.user_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  is_admin boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);

create index if not exists user_roles_admin_idx
  on public.user_roles (is_admin) where is_admin;

alter table public.user_roles enable row level security;

create or replace function public.sync_user_role()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.user_roles (user_id)
  values (new.id)
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists sync_user_role_on_signup on auth.users;
create trigger sync_user_role_on_signup
  after insert on auth.users
  for each row execute function public.sync_user_role();

insert into public.user_roles (user_id)
select id from auth.users
on conflict (user_id) do nothing;

-- Bootstrap the project owner. Further changes are made from the admin UI.
update public.user_roles roles
set is_admin = true,
    updated_at = now()
from auth.users users
where users.id = roles.user_id
  and lower(users.email) = 'alekseygredasov@mail.ru';

create or replace function public.is_admin(p_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce((
    select roles.is_admin
    from public.user_roles roles
    where roles.user_id = p_user_id
  ), false);
$$;

create or replace function public.get_my_admin_status()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select public.is_admin(auth.uid());
$$;

drop policy if exists "Users can read their own role" on public.user_roles;
create policy "Users can read their own role"
  on public.user_roles for select to authenticated
  using (auth.uid() = user_id or public.is_admin(auth.uid()));

revoke all on table public.user_roles from public, anon, authenticated;
grant select on table public.user_roles to authenticated;
grant all on table public.user_roles to service_role;

create or replace function public.admin_set_user_admin(
  p_user_id uuid,
  p_is_admin boolean
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'Admin access required' using errcode = '42501';
  end if;
  if p_user_id = auth.uid() and not p_is_admin then
    raise exception 'You cannot remove your own admin access' using errcode = '22023';
  end if;
  if not exists (select 1 from auth.users where id = p_user_id) then
    raise exception 'User not found' using errcode = '22023';
  end if;

  insert into public.user_roles (user_id, is_admin, updated_at, updated_by)
  values (p_user_id, p_is_admin, now(), auth.uid())
  on conflict (user_id) do update set
    is_admin = excluded.is_admin,
    updated_at = excluded.updated_at,
    updated_by = excluded.updated_by;
  return p_is_admin;
end;
$$;

create table if not exists public.site_analytics_events (
  id bigint generated always as identity primary key,
  session_id uuid not null,
  user_id uuid references auth.users(id) on delete set null,
  event_type text not null check (event_type in ('page_view', 'click')),
  event_name text not null,
  page_path text not null,
  referrer_host text,
  occurred_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists site_analytics_time_idx
  on public.site_analytics_events (occurred_at desc);
create index if not exists site_analytics_type_time_idx
  on public.site_analytics_events (event_type, occurred_at desc);
create index if not exists site_analytics_session_time_idx
  on public.site_analytics_events (session_id, occurred_at desc);

alter table public.site_analytics_events enable row level security;
revoke all on table public.site_analytics_events from public, anon, authenticated;
grant all on table public.site_analytics_events to service_role;

create or replace function public.track_site_event(
  p_session_id uuid,
  p_event_type text,
  p_event_name text,
  p_page_path text,
  p_referrer_host text default null,
  p_metadata jsonb default '{}'::jsonb
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  current_user_id uuid := auth.uid();
begin
  if p_event_type not in ('page_view', 'click')
     or char_length(p_event_name) not between 1 and 120
     or char_length(p_page_path) not between 1 and 300
     or char_length(coalesce(p_referrer_host, '')) > 180
     or pg_column_size(coalesce(p_metadata, '{}'::jsonb)) > 4096 then
    raise exception 'Invalid analytics event' using errcode = '22023';
  end if;

  -- Logged-in administrators never enter product analytics.
  if current_user_id is not null and public.is_admin(current_user_id) then
    return false;
  end if;

  insert into public.site_analytics_events (
    session_id, user_id, event_type, event_name, page_path, referrer_host, metadata
  ) values (
    p_session_id,
    current_user_id,
    p_event_type,
    left(btrim(p_event_name), 120),
    left(p_page_path, 300),
    nullif(left(coalesce(p_referrer_host, ''), 180), ''),
    coalesce(p_metadata, '{}'::jsonb) - 'email' - 'name' - 'ip'
  );
  return true;
end;
$$;

create table if not exists public.provider_cost_rates (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  service text not null,
  model text not null,
  unit_type text not null check (unit_type in ('minute', 'token', 'request')),
  unit_price_usd numeric(14, 8) not null check (unit_price_usd >= 0),
  active_from timestamptz not null default now(),
  active_to timestamptz,
  source_url text,
  created_at timestamptz not null default now(),
  constraint provider_cost_rates_period check (active_to is null or active_to > active_from)
);

create unique index if not exists provider_cost_rates_active_unique
  on public.provider_cost_rates (provider, service, model, active_from);

insert into public.provider_cost_rates (
  provider, service, model, unit_type, unit_price_usd, active_from, source_url
) values (
  'openai',
  'speech_translation',
  'gpt-realtime-translate',
  'minute',
  0.034,
  '2026-01-01T00:00:00Z',
  'https://developers.openai.com/api/docs/models/gpt-realtime-translate'
)
on conflict (provider, service, model, active_from) do update set
  unit_price_usd = excluded.unit_price_usd,
  source_url = excluded.source_url;

create table if not exists public.provider_cost_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  provider text not null,
  service text not null,
  model text not null,
  amount_usd numeric(14, 6) not null check (amount_usd >= 0),
  amount_rub numeric(14, 2) check (amount_rub is null or amount_rub >= 0),
  usage_units numeric(18, 6) check (usage_units is null or usage_units >= 0),
  unit_type text check (unit_type is null or unit_type in ('minute', 'token', 'request')),
  source_type text,
  source_id text,
  is_estimate boolean not null default false,
  occurred_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb
);

create index if not exists provider_cost_events_time_idx
  on public.provider_cost_events (occurred_at desc);
create index if not exists provider_cost_events_user_time_idx
  on public.provider_cost_events (user_id, occurred_at desc);

alter table public.provider_cost_rates enable row level security;
alter table public.provider_cost_events enable row level security;
revoke all on table public.provider_cost_rates from public, anon, authenticated;
revoke all on table public.provider_cost_events from public, anon, authenticated;
grant all on table public.provider_cost_rates to service_role;
grant all on table public.provider_cost_events to service_role;

create or replace function public.admin_dashboard_summary(
  p_from timestamptz default (now() - interval '30 days'),
  p_to timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  result jsonb;
  rate_usd numeric := 0.034;
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'Admin access required' using errcode = '42501';
  end if;
  if p_from >= p_to then
    raise exception 'Invalid date range' using errcode = '22023';
  end if;

  select coalesce(rates.unit_price_usd, 0.034) into rate_usd
  from public.provider_cost_rates rates
  where rates.provider = 'openai'
    and rates.model = 'gpt-realtime-translate'
    and rates.active_from <= p_to
    and (rates.active_to is null or rates.active_to > p_from)
  order by rates.active_from desc
  limit 1;

  with filtered_events as (
    select * from public.site_analytics_events
    where occurred_at >= p_from and occurred_at < p_to
  ), non_admin_users as (
    select users.*
    from auth.users users
    left join public.user_roles roles on roles.user_id = users.id
    where not coalesce(roles.is_admin, false)
  ), plan_counts as (
    select coalesce(active_sub.plan_id, 'free') as plan_id, count(*)::int as count
    from non_admin_users users
    left join lateral (
      select subscriptions.plan_id
      from public.subscriptions subscriptions
      where subscriptions.user_id = users.id
        and subscriptions.status = 'active'
        and subscriptions.current_period_end > now()
      limit 1
    ) active_sub on true
    group by coalesce(active_sub.plan_id, 'free')
  ), day_series as (
    select generate_series(date_trunc('day', p_from), date_trunc('day', p_to - interval '1 second'), interval '1 day') as day
  ), daily as (
    select
      series.day,
      count(events.id) filter (where events.event_type = 'page_view')::int as page_views,
      count(distinct events.session_id) filter (where events.event_type = 'page_view')::int as visitors,
      count(events.id) filter (where events.event_type = 'click')::int as clicks,
      (select count(*)::int from non_admin_users users where users.created_at >= series.day and users.created_at < series.day + interval '1 day') as signups
    from day_series series
    left join filtered_events events
      on events.occurred_at >= series.day and events.occurred_at < series.day + interval '1 day'
    group by series.day
    order by series.day
  )
  select jsonb_build_object(
    'from', p_from,
    'to', p_to,
    'page_views', (select count(*) from filtered_events where event_type = 'page_view'),
    'visitors', (select count(distinct session_id) from filtered_events where event_type = 'page_view'),
    'clicks', (select count(*) from filtered_events where event_type = 'click'),
    'signups', (select count(*) from non_admin_users where created_at >= p_from and created_at < p_to),
    'total_users', (select count(*) from non_admin_users),
    'revenue_rub', coalesce((select sum(amount) from public.payments where status = 'succeeded' and not test and coalesce(paid_at, created_at) >= p_from and coalesce(paid_at, created_at) < p_to), 0),
    'test_revenue_rub', coalesce((select sum(amount) from public.payments where status = 'succeeded' and test and coalesce(paid_at, created_at) >= p_from and coalesce(paid_at, created_at) < p_to), 0),
    'estimated_cost_usd', coalesce((select sum(duration_seconds) / 60.0 * rate_usd from public.translation_sessions where ended_at >= p_from and ended_at < p_to), 0),
    'recorded_cost_usd', coalesce((select sum(amount_usd) from public.provider_cost_events where occurred_at >= p_from and occurred_at < p_to), 0),
    'plans', coalesce((select jsonb_object_agg(plan_id, count) from plan_counts), '{}'::jsonb),
    'daily', coalesce((select jsonb_agg(jsonb_build_object('date', day, 'page_views', page_views, 'visitors', visitors, 'clicks', clicks, 'signups', signups)) from daily), '[]'::jsonb),
    'top_pages', coalesce((select jsonb_agg(row_data) from (select jsonb_build_object('name', page_path, 'count', count(*)) as row_data from filtered_events where event_type = 'page_view' group by page_path order by count(*) desc limit 8) pages), '[]'::jsonb),
    'top_actions', coalesce((select jsonb_agg(row_data) from (select jsonb_build_object('name', event_name, 'count', count(*)) as row_data from filtered_events where event_type = 'click' group by event_name order by count(*) desc limit 8) actions), '[]'::jsonb)
  ) into result;

  return result;
end;
$$;

create or replace function public.admin_list_users(
  p_search text default '',
  p_plan text default 'all',
  p_from timestamptz default null,
  p_to timestamptz default null,
  p_limit integer default 100,
  p_offset integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  result jsonb;
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'Admin access required' using errcode = '42501';
  end if;
  if p_plan not in ('all', 'free', 'start', 'pro') or p_limit not between 1 and 250 or p_offset < 0 then
    raise exception 'Invalid filter' using errcode = '22023';
  end if;

  with user_rows as (
    select
      users.id as user_id,
      users.email,
      users.created_at,
      users.last_sign_in_at,
      coalesce(roles.is_admin, false) as is_admin,
      coalesce(active_sub.plan_id, 'free') as plan_id,
      coalesce(payments.total_paid_rub, 0) as total_paid_rub,
      coalesce(usage.usage_seconds, 0) as usage_seconds,
      coalesce(usage.session_count, 0) as session_count
    from auth.users users
    left join public.user_roles roles on roles.user_id = users.id
    left join lateral (
      select subscriptions.plan_id
      from public.subscriptions subscriptions
      where subscriptions.user_id = users.id
        and subscriptions.status = 'active'
        and subscriptions.current_period_end > now()
      limit 1
    ) active_sub on true
    left join lateral (
      select coalesce(sum(amount) filter (where status = 'succeeded' and not test), 0) as total_paid_rub
      from public.payments
      where user_id = users.id
        and (p_from is null or coalesce(paid_at, created_at) >= p_from)
        and (p_to is null or coalesce(paid_at, created_at) < p_to)
    ) payments on true
    left join lateral (
      select coalesce(sum(duration_seconds), 0) as usage_seconds, count(*)::int as session_count
      from public.translation_sessions
      where user_id = users.id
        and (p_from is null or ended_at >= p_from)
        and (p_to is null or ended_at < p_to)
    ) usage on true
    where (p_search = '' or users.email ilike '%' || left(p_search, 120) || '%')
      and (p_from is null or users.created_at >= p_from)
      and (p_to is null or users.created_at < p_to)
      and (p_plan = 'all' or coalesce(active_sub.plan_id, 'free') = p_plan)
    order by users.created_at desc
    limit p_limit offset p_offset
  )
  select coalesce(jsonb_agg(to_jsonb(user_rows)), '[]'::jsonb) into result from user_rows;
  return result;
end;
$$;

create or replace function public.admin_list_costs(
  p_search text default '',
  p_from timestamptz default (now() - interval '30 days'),
  p_to timestamptz default now(),
  p_limit integer default 100,
  p_offset integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  result jsonb;
  rate_usd numeric := 0.034;
begin
  if not public.is_admin(auth.uid()) then
    raise exception 'Admin access required' using errcode = '42501';
  end if;
  if p_from >= p_to or p_limit not between 1 and 250 or p_offset < 0 then
    raise exception 'Invalid filter' using errcode = '22023';
  end if;

  select coalesce(rates.unit_price_usd, 0.034) into rate_usd
  from public.provider_cost_rates rates
  where rates.provider = 'openai' and rates.model = 'gpt-realtime-translate'
    and rates.active_from <= p_to and (rates.active_to is null or rates.active_to > p_from)
  order by rates.active_from desc limit 1;

  with cost_rows as (
    select
      users.id as user_id,
      users.email,
      coalesce(active_sub.plan_id, 'free') as plan_id,
      coalesce(usage.usage_seconds, 0) as usage_seconds,
      coalesce(usage.session_count, 0) as session_count,
      round((coalesce(usage.usage_seconds, 0) / 60.0 * rate_usd)::numeric, 4) as estimated_cost_usd,
      round(coalesce(costs.recorded_cost_usd, 0)::numeric, 4) as recorded_cost_usd,
      coalesce(costs.recorded_cost_rub, 0) as recorded_cost_rub
    from auth.users users
    left join lateral (
      select subscriptions.plan_id from public.subscriptions subscriptions
      where subscriptions.user_id = users.id and subscriptions.status = 'active' and subscriptions.current_period_end > now()
      limit 1
    ) active_sub on true
    left join lateral (
      select coalesce(sum(duration_seconds), 0) as usage_seconds, count(*)::int as session_count
      from public.translation_sessions sessions
      where sessions.user_id = users.id and sessions.ended_at >= p_from and sessions.ended_at < p_to
    ) usage on true
    left join lateral (
      select coalesce(sum(amount_usd), 0) as recorded_cost_usd, coalesce(sum(amount_rub), 0) as recorded_cost_rub
      from public.provider_cost_events events
      where events.user_id = users.id and events.occurred_at >= p_from and events.occurred_at < p_to
    ) costs on true
    where (p_search = '' or users.email ilike '%' || left(p_search, 120) || '%')
      and (coalesce(usage.usage_seconds, 0) > 0 or coalesce(costs.recorded_cost_usd, 0) > 0 or coalesce(costs.recorded_cost_rub, 0) > 0)
    order by (coalesce(costs.recorded_cost_usd, 0) + coalesce(usage.usage_seconds, 0) / 60.0 * rate_usd) desc
    limit p_limit offset p_offset
  )
  select coalesce(jsonb_agg(to_jsonb(cost_rows)), '[]'::jsonb) into result from cost_rows;
  return result;
end;
$$;

revoke all on function public.is_admin(uuid) from public, anon, authenticated;
revoke all on function public.get_my_admin_status() from public, anon, authenticated;
revoke all on function public.admin_set_user_admin(uuid, boolean) from public, anon, authenticated;
revoke all on function public.track_site_event(uuid, text, text, text, text, jsonb) from public, anon, authenticated;
revoke all on function public.admin_dashboard_summary(timestamptz, timestamptz) from public, anon, authenticated;
revoke all on function public.admin_list_users(text, text, timestamptz, timestamptz, integer, integer) from public, anon, authenticated;
revoke all on function public.admin_list_costs(text, timestamptz, timestamptz, integer, integer) from public, anon, authenticated;

grant execute on function public.is_admin(uuid) to authenticated, service_role;
grant execute on function public.get_my_admin_status() to authenticated;
grant execute on function public.admin_set_user_admin(uuid, boolean) to authenticated;
grant execute on function public.track_site_event(uuid, text, text, text, text, jsonb) to anon, authenticated;
grant execute on function public.admin_dashboard_summary(timestamptz, timestamptz) to authenticated;
grant execute on function public.admin_list_users(text, text, timestamptz, timestamptz, integer, integer) to authenticated;
grant execute on function public.admin_list_costs(text, timestamptz, timestamptz, integer, integer) to authenticated;

