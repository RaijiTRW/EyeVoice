import {
  authenticatedUser,
  corsHeaders,
  json,
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
    if (typeof payload?.payment_id !== "string") {
      return json({ error: "Payment id is required" }, 400);
    }

    const paymentResponse = await yookassaRequest(
      `/payments/${encodeURIComponent(payload.payment_id)}`,
    );
    const payment = await paymentResponse.json().catch(() => null);
    if (!paymentResponse.ok || payment?.metadata?.user_id !== user.id) {
      return json({ error: "Payment not found" }, 404);
    }

    if (payment.status === "succeeded" && payment.paid === true) {
      const processResponse = await fetch(
        `${requiredEnv("SUPABASE_URL")}/functions/v1/yookassa-webhook`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ event: "payment.succeeded", object: { id: payment.id } }),
        },
      );
      if (!processResponse.ok) {
        console.error("Failed to process verified payment", await processResponse.text());
        return json({ error: "Payment activation is delayed" }, 502);
      }
    }

    return json({ status: payment.status, paid: Boolean(payment.paid) });
  } catch (error) {
    console.error("confirm-payment failed", error);
    return json({ error: "Unable to verify payment" }, 500);
  }
});
