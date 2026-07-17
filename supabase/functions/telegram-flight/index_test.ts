import { validateTelegramInitData } from "../_shared/telegram-init-data.ts";

// Covers valid, tampered, and expired Telegram payloads.

const encoder = new TextEncoder();

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

function toHex(bytes: Uint8Array): string {
  return Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function signedInitData(token: string, authDate: number): Promise<string> {
  const params = new URLSearchParams({
    auth_date: String(authDate),
    query_id: "test-query",
    user: JSON.stringify({ id: 123456789, first_name: "Paper", last_name: "Pilot", language_code: "en" }),
  });
  const checkString = Array.from(params.entries())
    .sort(([left], [right]) => left.localeCompare(right))
    .map(([key, value]) => `${key}=${value}`)
    .join("\n");
  const secret = await hmacSha256(encoder.encode("WebAppData"), token);
  params.set("hash", toHex(await hmacSha256(secret, checkString)));
  return params.toString();
}

Deno.test("accepts valid Telegram initData", async () => {
  const now = 1_800_000_000;
  const result = await validateTelegramInitData(await signedInitData("123:test-token", now), "123:test-token", {
    nowSeconds: now,
  });
  if (result.user.id !== 123456789 || result.displayName !== "Paper Pilot") {
    throw new Error("Valid Telegram identity was not returned");
  }
});

Deno.test("rejects a tampered Telegram user", async () => {
  const now = 1_800_000_000;
  const initData = (await signedInitData("123:test-token", now)).replace("123456789", "987654321");
  let rejected = false;
  try {
    await validateTelegramInitData(initData, "123:test-token", { nowSeconds: now });
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error("Tampered Telegram initData was accepted");
});

Deno.test("rejects expired Telegram initData", async () => {
  const now = 1_800_000_000;
  let rejected = false;
  try {
    await validateTelegramInitData(await signedInitData("123:test-token", now - 7200), "123:test-token", {
      nowSeconds: now,
      maxAgeSeconds: 3600,
    });
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error("Expired Telegram initData was accepted");
});
