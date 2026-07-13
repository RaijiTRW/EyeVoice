import {
  adminHeaders,
  isPlanId,
  json,
  paidPlans,
  requiredEnv,
  yookassaRequest,
} from "../_shared/billing.ts";

type DueSubscription = {
  user_id: string;
  plan_id: "start" | "pro";
  pending_plan_id: "free" | "start" | "pro" | null;
  provider_payment_method_id: string;
};

async function rest(path: string, init: RequestInit = {}) {
  return fetch(`${requiredEnv("SUPABASE_URL")}/rest/v1/${path}`, {
    ...init,
    headers: { ...adminHeaders(), ...(init.headers ?? {}) },
  });
}

async function patchSubscription(userId: string, updates: Record<string, unknown>) {
  const response = await rest(`subscriptions?user_id=eq.${encodeURIComponent(userId)}`, {
    method: "PATCH",
    body: JSON.stringify({ ...updates, updated_at: new Date().toISOString() }),
  });
  if (!response.ok) throw new Error(await response.text());
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const configResponse = await rest("billing_cron_config?singleton=eq.true&select=secret&limit=1");
    const configRows = configResponse.ok ? await configResponse.json() : [];
    const expectedSecret = configRows?.[0]?.secret;
    if (typeof expectedSecret !== "string" || request.headers.get("x-cron-secret") !== expectedSecret) {
      return json({ error: "Unauthorized" }, 401);
    }

    await rest("rpc/expire_due_subscriptions", {
      method: "POST",
      body: "{}",
    });
    const claimResponse = await rest("rpc/claim_due_subscriptions", {
      method: "POST",
      body: "{}",
    });
    if (!claimResponse.ok) throw new Error(await claimResponse.text());
    const subscriptions = await claimResponse.json() as DueSubscription[];

    const results: Array<{ user_id: string; status: string }> = [];
    for (const subscription of subscriptions) {
      const nextPlan = subscription.pending_plan_id ?? subscription.plan_id;
      if (!isPlanId(nextPlan)) continue;

      try {
        const response = await yookassaRequest("/payments", {
          method: "POST",
          headers: { "Idempotence-Key": crypto.randomUUID() },
          body: JSON.stringify({
            amount: { value: paidPlans[nextPlan].amount, currency: "RUB" },
            capture: true,
            payment_method_id: subscription.provider_payment_method_id,
            description: `${paidPlans[nextPlan].title} — автопродление`,
            metadata: {
              user_id: subscription.user_id,
              plan_id: nextPlan,
              product_type: "plan",
              renewal: true,
            },
          }),
        });
        const payment = await response.json().catch(() => null);
        if (!response.ok || typeof payment?.id !== "string") {
          const message = payment?.description ?? payment?.code ?? "Renewal payment failed";
          await patchSubscription(subscription.user_id, {
            auto_renew: false,
            renewal_lock_until: null,
            renewal_error: String(message),
          });
          results.push({ user_id: subscription.user_id, status: "failed" });
          continue;
        }

        const saveResponse = await rest("payments?on_conflict=provider_payment_id", {
          method: "POST",
          headers: adminHeaders("resolution=merge-duplicates"),
          body: JSON.stringify({
            user_id: subscription.user_id,
            provider_payment_id: payment.id,
            plan_id: nextPlan,
            product_type: "plan",
            quantity_hours: null,
            amount: paidPlans[nextPlan].amount,
            currency: "RUB",
            status: payment.status ?? "pending",
            provider: "yookassa",
            test: Boolean(payment.test),
            payment_method: payment.payment_method?.type ?? null,
            raw: payment,
          }),
        });
        if (!saveResponse.ok) throw new Error(await saveResponse.text());

        if (payment.status === "canceled") {
          await patchSubscription(subscription.user_id, {
            auto_renew: false,
            renewal_lock_until: null,
            renewal_error: payment.cancellation_details?.reason ?? "Payment canceled",
          });
        } else {
          await patchSubscription(subscription.user_id, {
            renewal_lock_until: new Date(Date.now() + 24 * 60 * 60 * 1000).toISOString(),
          });
        }
        results.push({ user_id: subscription.user_id, status: payment.status ?? "pending" });
      } catch (error) {
        await patchSubscription(subscription.user_id, {
          auto_renew: false,
          renewal_lock_until: null,
          renewal_error: error instanceof Error ? error.message : "Renewal failed",
        });
        results.push({ user_id: subscription.user_id, status: "failed" });
      }
    }

    return json({ processed: results.length, results });
  } catch (error) {
    console.error("renew-subscriptions failed", error);
    return json({ error: "Renewal worker failed" }, 500);
  }
});
