import {
  constantTimeEqual,
  normalizeBotUsername,
  parseBotCommand,
  telegramApiRateLimit,
} from "./telegram-bot-safety.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("normalizes configured Telegram bot usernames", () => {
  assert(normalizeBotUsername(" @PaperFlightBot ") === "paperflightbot", "username mismatch");
});

Deno.test("parses private bot commands and confirmation arguments", () => {
  const deletion = parseBotCommand("/delete_me@PaperFlightBot confirm");
  assert(deletion?.command === "delete_me", "command mismatch");
  assert(deletion.argument === "confirm", "argument mismatch");
  assert(parseBotCommand("ordinary message") === null, "ordinary text must not be a command");
});

Deno.test("compares secrets without early character exits", () => {
  assert(constantTimeEqual("correct-secret", "correct-secret"), "equal secrets rejected");
  assert(!constantTimeEqual("correct-secret", "wrong--secret"), "different secrets accepted");
  assert(!constantTimeEqual("short", "longer"), "different lengths accepted");
});

Deno.test("uses conservative per-action API limits", () => {
  assert(telegramApiRateLimit("profile") === 20, "profile limit mismatch");
  assert(telegramApiRateLimit("create_challenge") === 3, "challenge limit mismatch");
  assert(telegramApiRateLimit("unknown") === null, "unknown action must be rejected");
});
