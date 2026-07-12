import {
  adminHeaders,
  isPlanId,
  json,
  paidPlans,
  requiredEnv,
  yookassaRequest,
} from "../_shared/billing.ts";

type YooPayment = {
  id?: string;
  status?: string;
  paid?: boolean;
  test?: boolean;
  amount?: { value?: string; currency?: string };
  metadata?: { user_id?: string; plan_id?: string };
  payment_method?: { type?: string; id?: string; saved?: boolean };
  captured_at?: string;
  created_at?: string;
};

async function rest(path: string, init: RequestInit = {}) {
  return fetch(`${requiredEnv("SUPABASE_URL")}/rest/v1/${path}`, {
    ...init,
    headers: { ...adminHeaders(), ...(init.headers ?? {}) },
  });
}

function addMonth(from: Date) {
  const result = new Date(from);
  result.setUTCMonth(result.getUTCMonth() + 1);
  return result;
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const notification = await request.json().catch(() => null);
    const paymentId = notification?.object?.id;
    if (typeof paymentId !== "string") return json({ error: "Invalid notification" }, 400);

    // YooKassa notifications are verified by loading the canonical payment over
    // the authenticated API. No status or metadata from the incoming body is trusted.
    const verifyResponse = await yookassaRequest(`/payments/${encodeURIComponent(paymentId)}`);
    const payment = await verifyResponse.json().catch(() => null) as YooPayment | null;
    if (!verifyResponse.ok || !payment) return json({ error: "Payment verification failed" }, 400);

    const userId = payment.metadata?.user_id;
    const planId = payment.metadata?.plan_id;
    if (typeof userId !== "string" || !isPlanId(planId)) {
      return json({ error: "Invalid payment metadata" }, 400);
    }
    const expected = paidPlans[planId];
    if (payment.amount?.value !== expected.amount || payment.amount?.currency !== "RUB") {
      return json({ error: "Payment amount mismatch" }, 400);
    }

    const previousResponse = await rest(
      `payments?provider_payment_id=eq.${encodeURIComponent(paymentId)}&select=status&limit=1`,
    );
    const previousRows = previousResponse.ok ? await previousResponse.json() : [];
    const alreadyActivated = previousRows?.[0]?.status === "succeeded";

    const upsertResponse = await rest("payments?on_conflict=provider_payment_id", {
      method: "POST",
      headers: adminHeaders("resolution=merge-duplicates"),
      body: JSON.stringify({
        user_id: userId,
        provider_payment_id: paymentId,
        plan_id: planId,
        amount: expected.amount,
        currency: "RUB",
        status: payment.status ?? "pending",
        provider: "yookassa",
        test: Boolean(payment.test),
        payment_method: payment.payment_method?.type ?? null,
        paid_at: payment.captured_at ?? null,
        raw: payment,
        updated_at: new Date().toISOString(),
      }),
    });
    if (!upsertResponse.ok) throw new Error(await upsertResponse.text());

    if (payment.status === "succeeded" && payment.paid === true && !alreadyActivated) {
      const subscriptionResponse = await rest(
        `subscriptions?user_id=eq.${encodeURIComponent(userId)}&select=current_period_end&limit=1`,
      );
      const subscriptions = subscriptionResponse.ok ? await subscriptionResponse.json() : [];
      const now = new Date();
      const previousEnd = subscriptions?.[0]?.current_period_end
        ? new Date(subscriptions[0].current_period_end)
        : null;
      const periodStart = previousEnd && previousEnd > now ? previousEnd : now;
      const periodEnd = addMonth(periodStart);

      const activateResponse = await rest("subscriptions?on_conflict=user_id", {
        method: "POST",
        headers: adminHeaders("resolution=merge-duplicates"),
        body: JSON.stringify({
          user_id: userId,
          plan_id: planId,
          status: "active",
          current_period_start: periodStart.toISOString(),
          current_period_end: periodEnd.toISOString(),
          auto_renew: false,
          provider_payment_method_id: payment.payment_method?.id ?? null,
          updated_at: now.toISOString(),
        }),
      });
      if (!activateResponse.ok) throw new Error(await activateResponse.text());

      const userResponse = await fetch(
        `${requiredEnv("SUPABASE_URL")}/auth/v1/admin/users/${encodeURIComponent(userId)}`,
        { headers: adminHeaders() },
      );
      const authUser = userResponse.ok ? await userResponse.json() : {};
      const updateUserResponse = await fetch(
        `${requiredEnv("SUPABASE_URL")}/auth/v1/admin/users/${encodeURIComponent(userId)}`,
        {
          method: "PUT",
          headers: adminHeaders(),
          body: JSON.stringify({
            app_metadata: { ...(authUser.app_metadata ?? {}), plan: planId },
            user_metadata: { ...(authUser.user_metadata ?? {}), plan: planId },
          }),
        },
      );
      if (!updateUserResponse.ok) throw new Error(await updateUserResponse.text());
    }

    return json({ received: true });
  } catch (error) {
    console.error("yookassa-webhook failed", error);
    return json({ error: "Webhook processing failed" }, 500);
  }
});
