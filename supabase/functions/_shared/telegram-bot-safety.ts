export type ParsedBotCommand = {
  command: string;
  argument: string;
};

export function normalizeBotUsername(value: string): string {
  return value.trim().replace(/^@/, "").toLowerCase();
}

export function parseBotCommand(text: string): ParsedBotCommand | null {
  const match = text.trim().match(/^\/([a-z0-9_]+)(?:@([a-z0-9_]+))?(?:\s+([\s\S]*))?$/i);
  if (!match) return null;
  return {
    command: match[1].toLowerCase(),
    argument: (match[3] ?? "").trim(),
  };
}

export function constantTimeEqual(left: string, right: string): boolean {
  if (!left || left.length !== right.length) return false;
  let mismatch = 0;
  for (let index = 0; index < left.length; index += 1) {
    mismatch |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return mismatch === 0;
}

export function telegramApiRateLimit(action: string): number | null {
  const limits: Record<string, number> = {
    profile: 20,
    leaderboard: 30,
    start: 12,
    submit: 20,
    create_challenge: 3,
  };
  return limits[action] ?? null;
}
