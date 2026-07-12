-- Administrative views join billing and usage with the Supabase account email.
-- The service role is server-only and already has Auth Admin API access; this
-- explicit grant lets security-invoker views read the same account rows in SQL.
grant select on table auth.users to service_role;
