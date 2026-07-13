import {
  adminHeaders,
  authenticatedUser,
  corsHeaders,
  extraHourPrices,
  isPlanId,
  json,
  paidPlans,
  requiredEnv,
  yookassaRequest,
} from "../_shared/billing.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const user = await authenticatedUser(request.headers.get("Authorization"));
    if (!user) return json({ error: "Authentication required" }, 401);

    const payload = await request.json().catch(() => null);
    const productType = payload?.product_type === "extra_hours" ? "extra_hours" : "plan";
    let planId = payload?.plan_id;
    let quantityHours: number | null = null;
    let amount: string;
    let title: string;

    if (productType === "extra_hours") {
      quantityHours = Number(payload?.hours);
      if (!Number.isInteger(quantityHours) || quantityHours < 1 || quantityHours > 20) {
        return json({ error: "Choose between 1 and 20 hours" }, 400);
      }
      const now = new Date().toISOString();
      const subscriptionResponse = await fetch(
        `${requiredEnv("SUPABASE_URL")}/rest/v1/subscriptions` +
          `?user_id=eq.${encodeURIComponent(user.id)}` +
          "&status=eq.active" +
          `&current_period_start=lte.${encodeURIComponent(now)}` +
          `&current_period_end=gt.${encodeURIComponent(now)}` +
          "&select=plan_id&limit=1",
        { headers: adminHeaders() },
      );
      const subscriptions = subscriptionResponse.ok ? await subscriptionResponse.json() : [];
      planId = subscriptions?.[0]?.plan_id;
      if (!isPlanId(planId)) {
        return json({ error: "START or PRO is required for extra hours" }, 403);
      }
      const total = extraHourPrices[planId] * quantityHours;
      amount = `${total}.00`;
      title = `EyeVoice — дополнительные часы (${quantityHours} ч)`;
    } else {
      if (!isPlanId(planId)) return json({ error: "Unknown plan" }, 400);
      amount = paidPlans[planId].amount;
      title = paidPlans[planId].title;
    }

    const siteUrl = requiredEnv("SITE_URL").replace(/\/$/, "");
    const idempotenceKey = crypto.randomUUID();
    const response = await yookassaRequest("/payments", {
      method: "POST",
      headers: { "Idempotence-Key": idempotenceKey },
      body: JSON.stringify({
        amount: { value: amount, currency: "RUB" },
        capture: true,
        save_payment_method: productType === "plan",
        confirmation: {
          type: "redirect",
          return_url: `${siteUrl}/profile?payment=return${productType === "extra_hours" ? "&section=limits" : ""}`,
        },
        description: title,
        metadata: {
          user_id: user.id,
          plan_id: planId,
          product_type: productType,
          quantity_hours: quantityHours,
        },
      }),
    });
    const payment = await response.json().catch(() => null);
    if (!response.ok) {
      console.error("YooKassa create payment failed", response.status, payment);
      const providerMessage = typeof payment?.description === "string"
        ? payment.description
        : typeof payment?.code === "string"
          ? payment.code
          : null;
      return json({
        error: providerMessage ?? "Payment service is temporarily unavailable",
        code: payment?.code ?? null,
      }, 502);
    }

    const confirmationUrl = payment?.confirmation?.confirmation_url;
    if (typeof payment?.id !== "string" || typeof confirmationUrl !== "string") {
      return json({ error: "Payment service returned an invalid response" }, 502);
    }

    const saveResponse = await fetch(
      `${requiredEnv("SUPABASE_URL")}/rest/v1/payments?on_conflict=provider_payment_id`,
      {
        method: "POST",
        headers: adminHeaders("resolution=merge-duplicates"),
        body: JSON.stringify({
          user_id: user.id,
          provider_payment_id: payment.id,
          plan_id: planId,
          product_type: productType,
          quantity_hours: quantityHours,
          amount,
          currency: "RUB",
          status: payment.status ?? "pending",
          provider: "yookassa",
          test: Boolean(payment.test),
          raw: payment,
        }),
      },
    );
    if (!saveResponse.ok) {
      console.error("Failed to persist pending payment", await saveResponse.text());
      return json({ error: "Unable to save payment" }, 500);
    }

    return json({ confirmation_url: confirmationUrl, payment_id: payment.id });
  } catch (error) {
    console.error("create-payment failed", error);
    return json({
      error: error instanceof Error ? error.message : "Payment service is temporarily unavailable",
    }, 500);
  }
});
