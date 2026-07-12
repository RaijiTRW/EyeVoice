import {
  adminHeaders,
  authenticatedUser,
  corsHeaders,
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
    const planId = payload?.plan_id;
    if (!isPlanId(planId)) return json({ error: "Unknown plan" }, 400);

    const plan = paidPlans[planId];
    const siteUrl = requiredEnv("SITE_URL").replace(/\/$/, "");
    const idempotenceKey = crypto.randomUUID();
    const response = await yookassaRequest("/payments", {
      method: "POST",
      headers: { "Idempotence-Key": idempotenceKey },
      body: JSON.stringify({
        amount: { value: plan.amount, currency: "RUB" },
        capture: true,
        confirmation: {
          type: "redirect",
          return_url: `${siteUrl}/profile?payment=return`,
        },
        description: plan.title,
        metadata: { user_id: user.id, plan_id: planId },
      }),
    });
    const payment = await response.json().catch(() => null);
    if (!response.ok) {
      console.error("YooKassa create payment failed", response.status, payment);
      return json({ error: "Payment service is temporarily unavailable" }, 502);
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
          amount: plan.amount,
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
    return json({ error: "Payment service is temporarily unavailable" }, 500);
  }
});
