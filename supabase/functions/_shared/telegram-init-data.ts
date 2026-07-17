// Telegram Mini App initData validation shared by server-side functions.
const encoder = new TextEncoder();

export type TelegramUser = {
  id: number;
  first_name?: string;
  last_name?: string;
  username?: string;
  language_code?: string;
};

export type VerifiedTelegramData = {
  authDate: number;
  displayName: string;
  user: TelegramUser;
};

function bytesToHex(bytes: Uint8Array): string {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

function constantTimeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false;
  let mismatch = 0;
  for (let index = 0; index < left.length; index += 1) {
    mismatch |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return mismatch === 0;
}

async function hmacSha256(key: Uint8Array, value: string): Promise<Uint8Array> {
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    key,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  return new Uint8Array(await crypto.subtle.sign("HMAC", cryptoKey, encoder.encode(value)));
}

function buildDisplayName(user: TelegramUser): string {
  const fullName = [user.first_name, user.last_name]
    .filter((part): part is string => typeof part === "string" && part.trim().length > 0)
    .join(" ")
    .replace(/\s+/g, " ")
    .trim();
  const fallback = user.username ? `@${user.username}` : `TG ${user.id}`;
  return Array.from(fullName || fallback).slice(0, 18).join("");
}

export async function validateTelegramInitData(
  initData: string,
  botToken: string,
  options: { maxAgeSeconds?: number; nowSeconds?: number } = {},
): Promise<VerifiedTelegramData> {
  if (!initData || initData.length > 12_000) throw new Error("Invalid Telegram initData");
  if (!botToken) throw new Error("Telegram bot token is not configured");

  const params = new URLSearchParams(initData);
  const receivedHash = params.get("hash")?.toLowerCase() ?? "";
  if (!/^[a-f0-9]{64}$/.test(receivedHash)) throw new Error("Invalid Telegram hash");

  const dataCheckString = Array.from(params.entries())
    .filter(([key]) => key !== "hash")
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([key, value]) => `${key}=${value}`)
    .join("\n");

  const secretKey = await hmacSha256(encoder.encode("WebAppData"), botToken);
  const expectedHash = bytesToHex(await hmacSha256(secretKey, dataCheckString));
  if (!constantTimeEqual(receivedHash, expectedHash)) throw new Error("Invalid Telegram signature");

  const authDate = Number(params.get("auth_date"));
  const nowSeconds = options.nowSeconds ?? Math.floor(Date.now() / 1000);
  const maxAgeSeconds = options.maxAgeSeconds ?? 3600;
  if (!Number.isInteger(authDate) || authDate <= 0) throw new Error("Invalid Telegram auth_date");
  if (authDate > nowSeconds + 60 || nowSeconds - authDate > maxAgeSeconds) {
    throw new Error("Expired Telegram initData");
  }

  let user: TelegramUser;
  try {
    user = JSON.parse(params.get("user") ?? "null") as TelegramUser;
  } catch {
    throw new Error("Invalid Telegram user data");
  }
  if (!user || !Number.isSafeInteger(user.id) || user.id <= 0) {
    throw new Error("Invalid Telegram user");
  }

  return { authDate, displayName: buildDisplayName(user), user };
}
