import { createClient } from "npm:@supabase/supabase-js@2";
import { validateTelegramInitData } from "../_shared/telegram-init-data.ts";
import { telegramApiRateLimit } from "../_shared/telegram-bot-safety.ts";

// This endpoint is the only trust boundary for Telegram identity and scores.

type RequestBody = {
  action?: "profile" | "leaderboard" | "start" | "submit" | "create_challenge";
  initData?: string;
  score?: number;
  sessionId?: string;
};

const DEFAULT_ORIGIN = "https://jergjer-ops.github.io";
const allowedOrigins = new Set(
  (Deno.env.get("ALLOWED_ORIGINS") ?? DEFAULT_ORIGIN)
    .split(",")
    .map((origin) => origin.trim())
    .filter(Boolean),
);

function jsonResponse(body: unknown, status: number, origin: string | null): Response {
  const allowOrigin = origin && allowedOrigins.has(origin) ? origin : DEFAULT_ORIGIN;
  return Response.json(body, {
    status,
    headers: {
      "Access-Control-Allow-Origin": allowOrigin,
      "Access-Control-Allow-Headers": "apikey, content-type",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Cache-Control": "no-store",
      Vary: "Origin",
    },
  });
}

function readKeyDictionary(name: string): string[] {
  try {
    const parsed = JSON.parse(Deno.env.get(name) ?? "{}") as Record<string, string>;
    return Object.values(parsed).filter(Boolean);
  } catch {
    return [];
  }
}

function publishableKeys(): string[] {
  return [
    ...readKeyDictionary("SUPABASE_PUBLISHABLE_KEYS"),
    Deno.env.get("SUPABASE_ANON_KEY") ?? "",
  ].filter(Boolean);
}

function secretKey(): string {
  return readKeyDictionary("SUPABASE_SECRET_KEYS")[0] ??
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
}

Deno.serve(async (request) => {
  const origin = request.headers.get("origin");
  if (origin && !allowedOrigins.has(origin)) {
    return jsonResponse({ error: "Origin is not allowed" }, 403, null);
  }

  if (request.method === "OPTIONS") return jsonResponse({ ok: true }, 200, origin);
  if (request.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405, origin);

  const contentType = request.headers.get("content-type")?.toLowerCase() ?? "";
  if (!contentType.startsWith("application/json")) {
    return jsonResponse({ error: "Unsupported media type" }, 415, origin);
  }

  const contentLength = Number(request.headers.get("content-length") ?? 0);
  if (contentLength > 16_384) return jsonResponse({ error: "Request is too large" }, 413, origin);

  const apiKey = request.headers.get("apikey") ?? "";
  if (!publishableKeys().includes(apiKey)) {
    return jsonResponse({ error: "Invalid API key" }, 401, origin);
  }

  const botToken = Deno.env.get("TELEGRAM_BOT_TOKEN") ?? "";
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const adminKey = secretKey();
  if (!botToken || !supabaseUrl || !adminKey) {
    return jsonResponse({ error: "Server is not configured" }, 503, origin);
  }

  let body: RequestBody;
  try {
    body = await request.json() as RequestBody;
  } catch {
    return jsonResponse({ error: "Invalid JSON" }, 400, origin);
  }

  let telegram;
  try {
    telegram = await validateTelegramInitData(body.initData ?? "", botToken);
  } catch (error) {
    const message = error instanceof Error ? error.message : "Telegram authentication failed";
    return jsonResponse({ error: message }, 401, origin);
  }

  const admin = createClient(supabaseUrl, adminKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const action = body.action ?? "";
  const requestLimit = telegramApiRateLimit(action);
  if (requestLimit === null) return jsonResponse({ error: "Unknown action" }, 400, origin);
  const rate = await admin.rpc("claim_telegram_api_request", {
    p_telegram_user_id: telegram.user.id,
    p_action: action,
    p_limit: requestLimit,
    p_window_seconds: 60,
  });
  if (rate.error) return jsonResponse({ error: "Unable to apply request limit" }, 503, origin);
  if (rate.data !== true) return jsonResponse({ error: "Too many requests" }, 429, origin);

  const startParam = new URLSearchParams(body.initData ?? "").get("start_param") ?? "";
  const challengeCode = /^c_[0-9a-f]{24}$/.test(startParam) ? startParam : "";

  if (body.action === "profile") {
    const playerKey = `telegram:${telegram.user.id}`;
    const { data, error } = await admin
      .from("leaderboard")
      .select("player_name,best_score,total_flights")
      .eq("player_key", playerKey)
      .maybeSingle();
    if (error) return jsonResponse({ error: "Unable to load profile" }, 400, origin);
    let challenge = null;
    if (challengeCode) {
      const opened = await admin.rpc("open_game_challenge", {
        p_telegram_user_id: telegram.user.id,
        p_code: challengeCode,
      });
      if (!opened.error) challenge = opened.data;
    }
    return jsonResponse({
      telegram: { id: telegram.user.id, name: telegram.displayName },
      profile: data ?? { player_name: telegram.displayName, best_score: 0, total_flights: 0 },
      challenge,
    }, 200, origin);
  }

  if (body.action === "leaderboard") {
    const { data, error } = await admin.rpc("register_telegram_game_visit", {
      p_telegram_user_id: telegram.user.id,
    });
    if (error) return jsonResponse({ error: "Unable to load leaderboard" }, 400, origin);
    return jsonResponse(data, 200, origin);
  }

  if (body.action === "start") {
    const { data, error } = await admin.rpc("start_flight_telegram", {
      p_telegram_user_id: telegram.user.id,
      p_name: telegram.displayName,
    });
    if (error) return jsonResponse({ error: "Unable to start flight" }, 400, origin);
    if (challengeCode) {
      await admin.rpc("mark_game_challenge_flight", {
        p_telegram_user_id: telegram.user.id,
        p_code: challengeCode,
      });
    }
    return jsonResponse({ ...data, telegram: { id: telegram.user.id, name: telegram.displayName } }, 200, origin);
  }

  if (body.action === "submit") {
    if (
      typeof body.sessionId !== "string" ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(body.sessionId)
    ) {
      return jsonResponse({ error: "Invalid session" }, 400, origin);
    }
    if (!Number.isInteger(body.score) || (body.score as number) < 0 || (body.score as number) > 1000) {
      return jsonResponse({ error: "Invalid score" }, 400, origin);
    }
    const { data, error } = await admin.rpc("submit_score_telegram", {
      p_telegram_user_id: telegram.user.id,
      p_session: body.sessionId,
      p_score: body.score,
    });
    if (error) return jsonResponse({ error: "Unable to submit score" }, 400, origin);
    let challenge = null;
    if (challengeCode) {
      const recorded = await admin.rpc("record_game_challenge_score", {
        p_telegram_user_id: telegram.user.id,
        p_code: challengeCode,
        p_score: body.score,
      });
      if (!recorded.error) challenge = recorded.data;
    }
    return jsonResponse({ ...data, challenge }, 200, origin);
  }

  if (body.action === "create_challenge") {
    if (!Number.isInteger(body.score) || (body.score as number) < 1 || (body.score as number) > 1000) {
      return jsonResponse({ error: "Complete a scored flight first" }, 400, origin);
    }
    const { data, error } = await admin.rpc("create_game_challenge", {
      p_telegram_user_id: telegram.user.id,
      p_name: telegram.displayName,
      p_score: body.score,
    });
    if (error) return jsonResponse({ error: "Unable to create challenge" }, 400, origin);
    return jsonResponse(data, 200, origin);
  }

  return jsonResponse({ error: "Unknown action" }, 400, origin);
});
