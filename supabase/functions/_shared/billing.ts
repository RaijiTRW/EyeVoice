export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export type PlanId = "start" | "pro";
export type ProductType = "plan" | "extra_hours";

export const paidPlans: Record<PlanId, { amount: string; title: string }> = {
  start: { amount: "1990.00", title: "EyeVoice START — доступ на 1 месяц" },
  pro: { amount: "4990.00", title: "EyeVoice PRO — доступ на 1 месяц" },
};

export const extraHourPrices: Record<PlanId, number> = {
  start: 299,
  pro: 199,
};

export function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

export function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing server secret: ${name}`);
  return value;
}

export async function yookassaRequest(path: string, init: RequestInit = {}) {
  const shopId = requiredEnv("YOOKASSA_SHOP_ID");
  const secretKey = requiredEnv("YOOKASSA_SECRET_KEY");
  return fetch(`https://api.yookassa.ru/v3${path}`, {
    ...init,
    headers: {
      Authorization: `Basic ${btoa(`${shopId}:${secretKey}`)}`,
      "Content-Type": "application/json",
      ...(init.headers ?? {}),
    },
  });
}

export function adminHeaders(prefer?: string) {
  const serviceKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
  return {
    apikey: serviceKey,
    Authorization: `Bearer ${serviceKey}`,
    "Content-Type": "application/json",
    ...(prefer ? { Prefer: prefer } : {}),
  };
}

export async function authenticatedUser(authorization: string | null) {
  if (!authorization?.startsWith("Bearer ")) return null;
  const response = await fetch(`${requiredEnv("SUPABASE_URL")}/auth/v1/user`, {
    headers: {
      apikey: requiredEnv("SUPABASE_ANON_KEY"),
      Authorization: authorization,
    },
  });
  if (!response.ok) return null;
  const user = await response.json();
  return typeof user?.id === "string" ? user : null;
}

export function isPlanId(value: unknown): value is PlanId {
  return value === "start" || value === "pro";
}

export function isProductType(value: unknown): value is ProductType {
  return value === "plan" || value === "extra_hours";
}
