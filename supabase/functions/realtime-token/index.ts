const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function sha256(value: string) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const authorization = request.headers.get("Authorization");
  const supabaseURL = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const openAIKey = Deno.env.get("OPENAI_API_KEY");

  if (!authorization?.startsWith("Bearer ")) {
    return json({ error: "Authentication required" }, 401);
  }
  if (!supabaseURL || !supabaseAnonKey || !serviceRoleKey || !openAIKey) {
    return json({ error: "Server configuration is incomplete" }, 503);
  }

  const userResponse = await fetch(`${supabaseURL}/auth/v1/user`, {
    headers: {
      apikey: supabaseAnonKey,
      Authorization: authorization,
    },
  });
  if (!userResponse.ok) {
    return json({ error: "Invalid or expired session" }, 401);
  }

  const user = await userResponse.json() as { id?: string };
  if (!user.id) {
    return json({ error: "Invalid account" }, 401);
  }

  const adminHeaders = {
    apikey: serviceRoleKey,
    Authorization: `Bearer ${serviceRoleKey}`,
  };
  const subscriptionResponse = await fetch(
    `${supabaseURL}/rest/v1/subscriptions?user_id=eq.${encodeURIComponent(user.id)}&status=eq.active&current_period_end=gt.${encodeURIComponent(new Date().toISOString())}&select=plan_id&limit=1`,
    { headers: adminHeaders },
  );
  const subscriptions = subscriptionResponse.ok ? await subscriptionResponse.json() : [];
  const plan = subscriptions?.[0]?.plan_id === "pro"
    ? "pro"
    : subscriptions?.[0]?.plan_id === "start"
      ? "start"
      : "free";
  const limits = { free: 30 * 60, start: 5 * 60 * 60, pro: 15 * 60 * 60 };
  const monthStart = new Date();
  monthStart.setUTCDate(1);
  monthStart.setUTCHours(0, 0, 0, 0);
  const usageResponse = await fetch(
    `${supabaseURL}/rest/v1/translation_sessions?user_id=eq.${encodeURIComponent(user.id)}&ended_at=gte.${encodeURIComponent(monthStart.toISOString())}&select=duration_seconds`,
    { headers: adminHeaders },
  );
  const sessions = usageResponse.ok ? await usageResponse.json() : [];
  const usedSeconds = sessions.reduce(
    (total: number, session: { duration_seconds?: number }) =>
      total + Math.max(0, Number(session.duration_seconds) || 0),
    0,
  );
  if (usedSeconds >= limits[plan]) {
    return json({ error: "Monthly translation limit reached", plan }, 402);
  }

  let payload: { mode?: string; target_language?: string; voice?: string };
  try {
    payload = await request.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const mode = payload.mode === "voice" ? "voice" : "sync";
  const targetLanguage = String(payload.target_language ?? "en")
    .trim()
    .toLowerCase();
  const voice = String(payload.voice ?? "marin").trim().toLowerCase();

  if (!/^[a-z]{2,8}(-[a-z]{2,8})?$/.test(targetLanguage)) {
    return json({ error: "Unsupported target language" }, 400);
  }
  if (!/^[a-z0-9_-]{2,32}$/.test(voice)) {
    return json({ error: "Unsupported voice" }, 400);
  }

  const translation = mode === "sync";
  const endpoint = translation
    ? "https://api.openai.com/v1/realtime/translations/client_secrets"
    : "https://api.openai.com/v1/realtime/client_secrets";
  const session = translation
    ? {
        model: "gpt-realtime-translate",
        audio: { output: { language: targetLanguage } },
      }
    : {
        type: "realtime",
        model: "gpt-realtime-2.1-mini",
        audio: { output: { voice } },
      };

  const openAIResponse = await fetch(endpoint, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${openAIKey}`,
      "Content-Type": "application/json",
      "OpenAI-Safety-Identifier": await sha256(user.id),
    },
    body: JSON.stringify({ session }),
  });

  const responseBody = await openAIResponse.json().catch(() => null);
  if (!openAIResponse.ok) {
    console.error("OpenAI client secret request failed", openAIResponse.status, responseBody);
    return json({ error: "Realtime service is temporarily unavailable" }, 502);
  }

  const value = responseBody?.value;
  if (typeof value !== "string" || value.length === 0) {
    return json({ error: "Realtime service returned an invalid token" }, 502);
  }

  return json({
    value,
    expires_at: responseBody.expires_at ?? null,
  });
});
