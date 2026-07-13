import {
  authenticatedUser,
  corsHeaders,
  json,
} from "../_shared/billing.ts";
import { getUsageBalance } from "../_shared/usage.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const user = await authenticatedUser(request.headers.get("Authorization"));
    if (!user) return json({ error: "Authentication required" }, 401);
    return json(await getUsageBalance(user.id));
  } catch (error) {
    console.error("usage-balance failed", error);
    return json({ error: "Unable to load usage balance" }, 500);
  }
});

