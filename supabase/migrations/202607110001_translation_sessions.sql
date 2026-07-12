create table if not exists public.translation_sessions (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  started_at timestamptz not null,
  ended_at timestamptz not null,
  duration_seconds double precision not null check (duration_seconds >= 0),
  source_id text not null,
  source_name text not null,
  source_language text not null,
  target_language text not null,
  created_at timestamptz not null default now(),
  constraint translation_sessions_time_order check (ended_at >= started_at)
);

create index if not exists translation_sessions_user_ended_idx
  on public.translation_sessions (user_id, ended_at desc);

alter table public.translation_sessions enable row level security;

drop policy if exists "Users can read their translation sessions"
  on public.translation_sessions;
create policy "Users can read their translation sessions"
  on public.translation_sessions
  for select
  to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users can insert their translation sessions"
  on public.translation_sessions;
create policy "Users can insert their translation sessions"
  on public.translation_sessions
  for insert
  to authenticated
  with check (auth.uid() = user_id);

revoke all on table public.translation_sessions from anon;
grant select, insert on table public.translation_sessions to authenticated;
