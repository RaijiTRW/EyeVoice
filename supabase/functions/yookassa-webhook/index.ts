import {
  adminHeaders,
  extraHourPrices,
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
  metadata?: {
    user_id?: string;
    plan_id?: string;
    product_type?: string;
    quantity_hours?: number | string | null;
    renewal?: boolean | string;
  };
  payment_method?: {
    type?: string;
    id?: string;
    saved?: boolean;
    title?: string;
    card?: { last4?: string };
  };
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
    const productType = payment.metadata?.product_type === "extra_hours" ? "extra_hours" : "plan";
    const quantityHours = productType === "extra_hours"
      ? Number(payment.metadata?.quantity_hours)
      : null;
    if (productType === "extra_hours" &&
      (!Number.isInteger(quantityHours) || quantityHours! < 1 || quantityHours! > 20)) {
      return json({ error: "Invalid extra-hours metadata" }, 400);
    }
    const expectedAmount = productType === "extra_hours"
      ? `${extraHourPrices[planId] * quantityHours!}.00`
      : paidPlans[planId].amount;
    if (payment.amount?.value !== expectedAmount || payment.amount?.currency !== "RUB") {
      return json({ error: "Payment amount mismatch" }, 400);
    }

    const previousResponse = await rest(
      `payments?provider_payment_id=eq.${encodeURIComponent(paymentId)}&select=status&limit=1`,
    );
    const previousRows = previousResponse.ok ? await previousResponse.json() : [];
    const alreadyActivated = previousRows?.[0]?.status === "succeeded";

    if (payment.status === "succeeded" && payment.paid === true && !alreadyActivated) {
      const now = new Date();
      if (productType === "extra_hours") {
        const subscriptionResponse = await rest(
          `subscriptions?user_id=eq.${encodeURIComponent(userId)}` +
            "&status=eq.active" +
            `&current_period_start=lte.${encodeURIComponent(now.toISOString())}` +
            `&current_period_end=gt.${encodeURIComponent(now.toISOString())}` +
            "&select=plan_id&limit=1",
        );
        const subscriptions = subscriptionResponse.ok ? await subscriptionResponse.json() : [];
        if (subscriptions?.[0]?.plan_id !== planId) {
          throw new Error("Paid plan is no longer active for extra hours");
        }
        const addHoursResponse = await rest("rpc/add_usage_hours", {
          method: "POST",
          body: JSON.stringify({
            p_user_id: userId,
            p_plan_id: planId,
            p_hours: quantityHours,
          }),
        });
        if (!addHoursResponse.ok) throw new Error(await addHoursResponse.text());
      } else {
        const periodStart = now;
        const periodEnd = addMonth(periodStart);
        const savedMethod = payment.payment_method?.saved === true &&
          typeof payment.payment_method?.id === "string";
        const isRenewal = payment.metadata?.renewal === true || payment.metadata?.renewal === "true";

        const activateResponse = await rest("subscriptions?on_conflict=user_id", {
          method: "POST",
          headers: adminHeaders("resolution=merge-duplicates"),
          body: JSON.stringify({
            user_id: userId,
            plan_id: planId,
            status: "active",
            current_period_start: periodStart.toISOString(),
            current_period_end: periodEnd.toISOString(),
            auto_renew: savedMethod || isRenewal,
            provider_payment_method_id: savedMethod || isRenewal
              ? payment.payment_method?.id ?? null
              : null,
            payment_method_title: payment.payment_method?.title ?? null,
            card_last4: payment.payment_method?.card?.last4 ?? null,
            pending_plan_id: null,
            cancel_at_period_end: false,
            renewal_attempted_at: isRenewal ? now.toISOString() : null,
            renewal_lock_until: null,
            renewal_error: null,
            updated_at: now.toISOString(),
          }),
        });
        if (!activateResponse.ok) throw new Error(await activateResponse.text());

        const usageResponse = await rest("rpc/activate_usage_period", {
          method: "POST",
          body: JSON.stringify({
            p_user_id: userId,
            p_plan_id: planId,
            p_period_start: periodStart.toISOString(),
            p_period_end: periodEnd.toISOString(),
          }),
        });
        if (!usageResponse.ok) throw new Error(await usageResponse.text());

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
    }

    // Persist the terminal status only after its entitlement was granted. If
    // entitlement creation fails, YooKassa can safely retry the webhook.
    const upsertResponse = await rest("payments?on_conflict=provider_payment_id", {
      method: "POST",
      headers: adminHeaders("resolution=merge-duplicates"),
      body: JSON.stringify({
        user_id: userId,
        provider_payment_id: paymentId,
        plan_id: planId,
        product_type: productType,
        quantity_hours: quantityHours,
        amount: expectedAmount,
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

    return json({ received: true });
  } catch (error) {
    console.error("yookassa-webhook failed", error);
    return json({ error: "Webhook processing failed" }, 500);
  }
});
