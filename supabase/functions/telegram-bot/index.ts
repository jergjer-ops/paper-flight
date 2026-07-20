import { createClient } from "npm:@supabase/supabase-js@2";
import {
  constantTimeEqual,
  normalizeBotUsername,
  parseBotCommand,
} from "../_shared/telegram-bot-safety.ts";

type TelegramUpdate = {
  update_id?: number;
  message?: {
    chat?: { id?: number; type?: string };
    from?: { id?: number; language_code?: string };
    text?: string;
  };
};

type TelegramEnvelope<T = unknown> = {
  ok?: boolean;
  description?: string;
  result?: T;
};

type TelegramBotIdentity = {
  id: number;
  is_bot: boolean;
  first_name: string;
  username?: string;
};

const GAME_URL = "https://jergjer-ops.github.io/paper-flight/?v=30";
const FUNCTION_URL = "https://uqnendfdguugtcguceei.supabase.co/functions/v1/telegram-bot";
const ASSET_ROOT = "https://uqnendfdguugtcguceei.supabase.co/storage/v1/object/public/paper-flight-public/welcome";
const VIDEO_URL = `${ASSET_ROOT}/paper-flight-how-to-play.mp4`;
const POSTER_URL = `${ASSET_ROOT}/paper-flight-how-to-play-poster.png`;
const PRIVACY_URL = "https://jergjer-ops.github.io/paper-flight/privacy.html";
const SUPPORT_URL = "https://github.com/jergjer-ops/paper-flight/issues/new";
const MAX_REQUEST_BYTES = 65_536;

function response(body: unknown, status = 200): Response {
  return Response.json(body, { status, headers: { "Cache-Control": "no-store" } });
}

function secretKey(): string {
  try {
    const keys = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}") as Record<string, string>;
    const first = Object.values(keys).find(Boolean);
    if (first) return first;
  } catch { /* fall through */ }
  return Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
}

async function telegram<T = unknown>(method: string, payload: Record<string, unknown>): Promise<T> {
  const token = Deno.env.get("TELEGRAM_BOT_TOKEN") ?? "";
  const result = await fetch(`https://api.telegram.org/bot${token}/${method}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload),
  });
  const data = await result.json().catch(() => ({})) as TelegramEnvelope<T>;
  if (!result.ok || !data.ok) {
    throw new Error(
      `Telegram ${method} failed (${result.status}): ${data.description ?? "Unknown Telegram error"}`,
    );
  }
  return data.result as T;
}

function localized(languageCode: string, ru: string, en: string): string {
  return languageCode.toLowerCase().startsWith("ru") ? ru : en;
}

async function sendWelcome(chatId: number, languageCode = "") {
  const ru = languageCode.toLowerCase().startsWith("ru");
  const caption = ru
    ? "<b>✈️ PAPER FLIGHT — Бумажный полёт</b>\n\nЗапускай самолётик, пролетай между картонными препятствиями, собирай монеты и поднимайся в мировой рейтинг.\n\n🏆 Побей рекорд и брось вызов другу!"
    : "<b>✈️ PAPER FLIGHT</b>\n\nLaunch your paper plane, fly between cardboard obstacles, collect coins and climb the global leaderboard.\n\n🏆 Beat the record and challenge a friend!";
  const button = ru ? "🚀 Играть" : "🚀 Play";
  const common = {
    chat_id: chatId,
    caption,
    parse_mode: "HTML",
    reply_markup: { inline_keyboard: [[{ text: button, web_app: { url: GAME_URL } }]] },
  };
  try {
    await telegram("sendVideo", { ...common, video: VIDEO_URL, supports_streaming: true });
  } catch {
    await telegram("sendPhoto", { ...common, photo: POSTER_URL });
  }
}

async function sendText(chatId: number, text: string, replyMarkup?: Record<string, unknown>) {
  await telegram("sendMessage", {
    chat_id: chatId,
    text,
    parse_mode: "HTML",
    disable_web_page_preview: true,
    ...(replyMarkup ? { reply_markup: replyMarkup } : {}),
  });
}

async function sendHelp(chatId: number, languageCode: string) {
  const text = localized(
    languageCode,
    "<b>✈️ PAPER FLIGHT</b>\n\n/start — открыть игру\n/help — помощь\n/privacy — конфиденциальность\n/delete_me — удалить игровые данные\n/support — поддержка\n\nБот отвечает только на ваши команды и не рассылает сообщения без запроса.",
    "<b>✈️ PAPER FLIGHT</b>\n\n/start — open the game\n/help — help\n/privacy — privacy\n/delete_me — delete game data\n/support — support\n\nThe bot replies only to your commands and never sends unsolicited messages.",
  );
  await sendText(chatId, text);
}

async function sendPrivacy(chatId: number, languageCode: string) {
  await sendText(
    chatId,
    localized(
      languageCode,
      "Игра хранит Telegram ID, отображаемое имя и игровые результаты. Политика объясняет цели обработки и порядок удаления данных.",
      "The game stores your Telegram ID, display name, and game results. The policy explains why they are processed and how to delete them.",
    ),
    { inline_keyboard: [[{ text: localized(languageCode, "🔒 Открыть политику", "🔒 Open privacy policy"), url: PRIVACY_URL }]] },
  );
}

async function sendSupport(chatId: number, languageCode: string) {
  await sendText(
    chatId,
    localized(
      languageCode,
      "Если игра не запускается, откройте страницу поддержки. Не публикуйте токены, коды входа и Telegram ID.",
      "If the game does not start, open the support page. Never publish tokens, login codes, or your Telegram ID.",
    ),
    { inline_keyboard: [[{ text: localized(languageCode, "🛟 Поддержка", "🛟 Support"), url: SUPPORT_URL }]] },
  );
}

async function deletePlayerData(
  admin: ReturnType<typeof createClient>,
  telegramUserId: number,
): Promise<void> {
  const result = await admin.rpc("delete_telegram_player_data", {
    p_telegram_user_id: telegramUserId,
  });
  if (result.error) throw new Error("Unable to delete Telegram player data");
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return response({ error: "Method not allowed" }, 405);

  const contentType = request.headers.get("content-type")?.toLowerCase() ?? "";
  const contentLength = Number(request.headers.get("content-length") ?? 0);
  if (contentLength > MAX_REQUEST_BYTES) return response({ error: "Request is too large" }, 413);
  if (contentType && !contentType.startsWith("application/json")) {
    return response({ error: "Unsupported media type" }, 415);
  }

  const botToken = Deno.env.get("TELEGRAM_BOT_TOKEN") ?? "";
  const webhookSecret = Deno.env.get("TELEGRAM_WEBHOOK_SECRET") ?? "";
  const setupSecret = Deno.env.get("TELEGRAM_SETUP_SECRET") ?? "";
  const expectedUsername = normalizeBotUsername(Deno.env.get("TELEGRAM_EXPECTED_USERNAME") ?? "");
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const adminKey = secretKey();
  if (!botToken || !webhookSecret || !setupSecret || !expectedUsername || !supabaseUrl || !adminKey) {
    return response({ error: "Server is not configured" }, 503);
  }

  if (constantTimeEqual(request.headers.get("x-paper-flight-setup") ?? "", setupSecret)) {
    const identity = await telegram<TelegramBotIdentity>("getMe", {});
    const actualUsername = normalizeBotUsername(identity.username ?? "");
    if (!identity.is_bot || actualUsername !== expectedUsername) {
      return response({
        error: "Bot token does not match TELEGRAM_EXPECTED_USERNAME",
        actual_username: identity.username ?? null,
      }, 409);
    }
    await telegram("setMyCommands", {
      commands: [
        { command: "start", description: "Open PAPER FLIGHT" },
        { command: "help", description: "Help and commands" },
        { command: "privacy", description: "Privacy policy" },
        { command: "delete_me", description: "Delete my game data" },
        { command: "support", description: "Support" },
      ],
    });
    const webhookResult = await telegram<boolean>("setWebhook", {
      url: FUNCTION_URL,
      secret_token: webhookSecret,
      allowed_updates: ["message"],
      drop_pending_updates: true,
    });
    return response({
      ok: true,
      webhook: webhookResult,
      bot: { id: identity.id, username: identity.username },
    });
  }

  if (!constantTimeEqual(request.headers.get("x-telegram-bot-api-secret-token") ?? "", webhookSecret)) {
    return response({ error: "Unauthorized" }, 401);
  }

  let update: TelegramUpdate;
  try { update = await request.json() as TelegramUpdate; }
  catch { return response({ error: "Invalid JSON" }, 400); }
  if (!Number.isSafeInteger(update.update_id)) return response({ error: "Invalid update" }, 400);

  const botId = Number(botToken.split(":", 1)[0]);
  if (!Number.isSafeInteger(botId) || botId <= 0) return response({ error: "Invalid bot token" }, 503);

  const admin = createClient(supabaseUrl, adminKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const claim = await admin.from("telegram_webhook_receipts").insert({ bot_id: botId, update_id: update.update_id });
  if (claim.error?.code === "23505") return response({ ok: true, duplicate: true });
  if (claim.error) return response({ error: "Unable to claim update" }, 500);

  try {
    const message = update.message;
    const chatId = Number(message?.chat?.id ?? 0);
    const telegramUserId = Number(message?.from?.id ?? 0);
    const command = parseBotCommand(String(message?.text ?? ""));
    if (
      message?.chat?.type !== "private" ||
      !Number.isSafeInteger(chatId) || chatId <= 0 ||
      !Number.isSafeInteger(telegramUserId) || telegramUserId !== chatId ||
      !command
    ) {
      return response({ ok: true, ignored: true });
    }

    const rate = await admin.rpc("claim_telegram_bot_request", {
      p_telegram_user_id: telegramUserId,
      p_limit: 8,
      p_window_seconds: 60,
    });
    if (rate.error) throw new Error("Unable to apply Telegram bot rate limit");
    if (rate.data !== true) return response({ ok: true, rate_limited: true });

    const languageCode = message?.from?.language_code ?? "";
    if (command.command === "start") {
      await sendWelcome(chatId, languageCode);
    } else if (command.command === "help") {
      await sendHelp(chatId, languageCode);
    } else if (command.command === "privacy") {
      await sendPrivacy(chatId, languageCode);
    } else if (command.command === "support") {
      await sendSupport(chatId, languageCode);
    } else if (command.command === "delete_me") {
      if (command.argument.toLowerCase() === "confirm") {
        await deletePlayerData(admin, telegramUserId);
        await sendText(chatId, localized(languageCode, "Ваши серверные игровые данные удалены.", "Your server-side game data has been deleted."));
      } else {
        await sendText(
          chatId,
          localized(
            languageCode,
            "Это удалит профиль, результаты и историю полётов без возможности восстановления. Для подтверждения отправьте: <code>/delete_me confirm</code>",
            "This permanently deletes your profile, scores, and flight history. To confirm, send: <code>/delete_me confirm</code>",
          ),
        );
      }
    }
    if (Math.random() < 0.01) await admin.rpc("prune_telegram_bot_security_data");
    return response({ ok: true });
  } catch {
    await admin.from("telegram_webhook_receipts").delete().eq("bot_id", botId).eq("update_id", update.update_id);
    return response({ error: "Delivery failed" }, 500);
  }
});
