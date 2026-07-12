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

## YooKassa billing

`202607130001_billing.sql` creates server-owned payment and subscription
records. Authenticated users can read only their own records; only Edge
Functions using the service role can activate a paid plan.

Set these Edge Function secrets (never add their values to Git):

```sh
supabase secrets set \
  YOOKASSA_SHOP_ID=<shop-id> \
  YOOKASSA_SECRET_KEY=<secret-key> \
  SITE_URL=https://eyevoicetranslate.com
```

Deploy `create-payment`, `confirm-payment`, `yookassa-webhook`, and
`realtime-token`. In the YooKassa dashboard, subscribe `payment.succeeded` and
`payment.canceled` notifications to:

```text
https://seexmgivktuycodxrjhs.supabase.co/functions/v1/yookassa-webhook
```

The incoming notification is never trusted directly: the function reloads the
payment through the authenticated YooKassa API, checks its owner, plan, amount,
currency, and idempotently activates one month of access.

## Private account history

`202607130002_account_history.sql` creates a service-role-only event ledger and
automatically records account creation, payment status changes, subscription
changes, and completed translation sessions. It never stores audio or
translated text.

Administrative support and usage queries are available through these views:

- `admin_account_overview` — account, current plan, payment totals, and usage;
- `admin_monthly_usage` — monthly session count and translated seconds;
- `admin_account_timeline` — chronological account, billing, and usage events.

The views and the underlying `account_events` table are revoked from `anon` and
`authenticated`. Access them only from trusted server-side tooling using the
Supabase service role. Never expose the service role key to the website or app.
