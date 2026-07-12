# EyeVoice Supabase setup

Run `migrations/202607110001_translation_sessions.sql` in the Supabase SQL Editor.

The migration creates `public.translation_sessions`, enables Row Level Security,
and allows authenticated users to insert and read only their own translation
sessions. The macOS app writes a row after each completed translation session;
the profile page reads those rows to build real usage totals and charts.

## Realtime production token broker

`functions/realtime-token` keeps the permanent OpenAI API key on Supabase and
returns only short-lived Realtime client secrets to authenticated EyeVoice
accounts. The macOS app never embeds or accepts a provider API key.

1. Revoke any OpenAI key that has been pasted into source code, chat, logs, or a
   client device, then create a replacement key.
2. Save the replacement as the Edge Function secret `OPENAI_API_KEY` in the
   Supabase dashboard.
3. Deploy the `realtime-token` Edge Function with JWT verification enabled.

Never place `OPENAI_API_KEY` in `.env.local`, `Info.plist`, Swift source,
UserDefaults, or the application Keychain. Production entitlement and usage
limits should also be enforced in this server function before minting a token.
