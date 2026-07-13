import {
  adminHeaders,
  authenticatedUser,
  corsHeaders,
  json,
  requiredEnv,
  yookassaRequest,
} from "../_shared/billing.ts";

type Subscription = {
  user_id: string;
  plan_id: "start" | "pro";
  status: "active" | "expired" | "canceled";
  current_period_end: string;
  auto_renew: boolean;
  provider_payment_method_id: string | null;
  pending_plan_id: "free" | "start" | "pro" | null;
};

type YooPaymentMethod = {
  id?: string;
  status?: string;
  saved?: boolean;
  title?: string;
  metadata?: { user_id?: string };
  confirmation?: { confirmation_url?: string };
  card?: { last4?: string };
};

async function rest(path: string, init: RequestInit = {}) {
  return fetch(`${requiredEnv("SUPABASE_URL")}/rest/v1/${path}`, {
    ...init,
    headers: { ...adminHeaders(), ...(init.headers ?? {}) },
  });
}

async function activeSubscription(userId: string) {
  const now = new Date().toISOString();
  const response = await rest(
    `subscriptions?user_id=eq.${encodeURIComponent(userId)}` +
      "&status=eq.active" +
      `&current_period_end=gt.${encodeURIComponent(now)}` +
      "&select=*&limit=1",
  );
  if (!response.ok) throw new Error(await response.text());
  const rows = await response.json();
  return (rows?.[0] ?? null) as Subscription | null;
}

async function updateSubscription(userId: string, updates: Record<string, unknown>) {
  const response = await rest(`subscriptions?user_id=eq.${encodeURIComponent(userId)}`, {
    method: "PATCH",
    headers: adminHeaders("return=representation"),
    body: JSON.stringify({ ...updates, updated_at: new Date().toISOString() }),
  });
  if (!response.ok) throw new Error(await response.text());
  const rows = await response.json();
  return rows?.[0] ?? null;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const user = await authenticatedUser(request.headers.get("Authorization"));
    if (!user) return json({ error: "Authentication required" }, 401);

    const payload = await request.json().catch(() => null);
    const action = payload?.action;
    const subscription = await activeSubscription(user.id);
    if (!subscription) return json({ error: "Active paid plan required" }, 409);

    if (action === "cancel_plan") {
      const updated = await updateSubscription(user.id, {
        auto_renew: false,
        pending_plan_id: "free",
        cancel_at_period_end: true,
        renewal_error: null,
      });
      return json({ subscription: updated });
    }

    if (action === "schedule_downgrade") {
      if (subscription.plan_id !== "pro") {
        return json({ error: "Only PRO can be changed to START this way" }, 409);
      }
      if (!subscription.provider_payment_method_id) {
        return json({ error: "Link a card before scheduling the next plan" }, 409);
      }
      const updated = await updateSubscription(user.id, {
        auto_renew: true,
        pending_plan_id: "start",
        cancel_at_period_end: false,
        renewal_error: null,
      });
      return json({ subscription: updated });
    }

    if (action === "resume_plan") {
      if (!subscription.provider_payment_method_id) {
        return json({ error: "Link a card to enable automatic renewal" }, 409);
      }
      const updated = await updateSubscription(user.id, {
        auto_renew: true,
        pending_plan_id: null,
        cancel_at_period_end: false,
        renewal_error: null,
      });
      return json({ subscription: updated });
    }

    if (action === "unlink_card") {
      const updated = await updateSubscription(user.id, {
        provider_payment_method_id: null,
        payment_method_title: null,
        card_last4: null,
        auto_renew: false,
        renewal_error: null,
      });
      return json({ subscription: updated });
    }

    if (action === "create_card_binding") {
      const siteUrl = requiredEnv("SITE_URL").replace(/\/$/, "");
      const response = await yookassaRequest("/payment_methods", {
        method: "POST",
        headers: { "Idempotence-Key": crypto.randomUUID() },
        body: JSON.stringify({
          type: "bank_card",
          confirmation: {
            type: "redirect",
            return_url: `${siteUrl}/profile?billing=card-return`,
          },
          metadata: { user_id: user.id },
        }),
      });
      const method = await response.json().catch(() => null) as YooPaymentMethod | null;
      if (!response.ok) {
        console.error("YooKassa card binding failed", response.status, method);
        return json({ error: "Unable to start card linking" }, 502);
      }
      const confirmationUrl = method?.confirmation?.confirmation_url;
      if (typeof method?.id !== "string" || typeof confirmationUrl !== "string") {
        return json({ error: "Card service returned an invalid response" }, 502);
      }
      return json({ payment_method_id: method.id, confirmation_url: confirmationUrl });
    }

    if (action === "confirm_card_binding") {
      if (typeof payload?.payment_method_id !== "string") {
        return json({ error: "Payment method id is required" }, 400);
      }
      const response = await yookassaRequest(
        `/payment_methods/${encodeURIComponent(payload.payment_method_id)}`,
      );
      const method = await response.json().catch(() => null) as YooPaymentMethod | null;
      if (!response.ok || !method || method.metadata?.user_id !== user.id) {
        return json({ error: "Card binding not found" }, 404);
      }
      if (method.status === "pending") return json({ status: "pending" });
      if (method.status !== "active" || method.saved !== true) {
        return json({ status: "failed", error: "Card was not linked" }, 409);
      }
      const updated = await updateSubscription(user.id, {
        provider_payment_method_id: method.id,
        payment_method_title: method.title ?? null,
        card_last4: method.card?.last4 ?? null,
        auto_renew: true,
        cancel_at_period_end: false,
        pending_plan_id: subscription.pending_plan_id === "free"
          ? null
          : subscription.pending_plan_id,
        renewal_error: null,
      });
      return json({ status: "active", subscription: updated });
    }

    return json({ error: "Unknown action" }, 400);
  } catch (error) {
    console.error("manage-subscription failed", error);
    return json({ error: "Unable to update subscription" }, 500);
  }
});
