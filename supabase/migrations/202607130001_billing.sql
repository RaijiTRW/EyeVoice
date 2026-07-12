create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  provider_payment_id text not null unique,
  provider text not null check (provider in ('yookassa')),
  plan_id text not null check (plan_id in ('start', 'pro')),
  amount numeric(10, 2) not null check (amount > 0),
  currency text not null default 'RUB' check (currency = 'RUB'),
  status text not null check (status in ('pending', 'waiting_for_capture', 'succeeded', 'canceled')),
  payment_method text,
  test boolean not null default false,
  paid_at timestamptz,
  raw jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists payments_user_created_idx
  on public.payments (user_id, created_at desc);

create table if not exists public.subscriptions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  plan_id text not null check (plan_id in ('start', 'pro')),
  status text not null check (status in ('active', 'expired', 'canceled')),
  current_period_start timestamptz not null,
  current_period_end timestamptz not null,
  auto_renew boolean not null default false,
  provider_payment_method_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint subscription_period_order check (current_period_end > current_period_start)
);

alter table public.payments enable row level security;
alter table public.subscriptions enable row level security;

drop policy if exists "Users can read their payments" on public.payments;
create policy "Users can read their payments"
  on public.payments for select to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users can read their subscription" on public.subscriptions;
create policy "Users can read their subscription"
  on public.subscriptions for select to authenticated
  using (auth.uid() = user_id);

revoke all on table public.payments from anon, authenticated;
revoke all on table public.subscriptions from anon, authenticated;
grant select on table public.payments to authenticated;
grant select on table public.subscriptions to authenticated;
