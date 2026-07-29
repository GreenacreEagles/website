type LogLevel = "info" | "warn" | "error";

export type SafeLogFields = {
  requestId?: string;
  route?: string;
  operation?: string;
  durationMs?: number;
  status?: number;
  errorCode?: string;
  actorId?: string;
  entityId?: string;
  entityType?: string;
  callCount?: number;
  rateLimited?: boolean;
  [key: string]: string | number | boolean | undefined | null;
};

const SENSITIVE_KEY = /(password|token|secret|authorization|cookie|api[_-]?key|wwcc|card|cvv|payment[_-]?payload|turnstile)/i;

const scrub = (fields: SafeLogFields): Record<string, unknown> => {
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(fields)) {
    if (value === undefined) continue;
    if (SENSITIVE_KEY.test(key)) continue;
    if (typeof value === "string" && value.length > 500) {
      out[key] = `${value.slice(0, 500)}…`;
      continue;
    }
    out[key] = value;
  }
  return out;
};

const write = (level: LogLevel, message: string, fields: SafeLogFields = {}) => {
  const payload = {
    level,
    message,
    ts: new Date().toISOString(),
    ...scrub(fields)
  };
  const line = JSON.stringify(payload);
  if (level === "error") console.error(line);
  else if (level === "warn") console.warn(line);
  else console.info(line);
};

export const createRequestId = () => crypto.randomUUID();

export const logInfo = (message: string, fields?: SafeLogFields) => write("info", message, fields);
export const logWarn = (message: string, fields?: SafeLogFields) => write("warn", message, fields);
export const logError = (message: string, fields?: SafeLogFields) => write("error", message, fields);

export const withRequestLog = async <T>(
  fields: SafeLogFields,
  run: (requestId: string) => Promise<T>
): Promise<T> => {
  const requestId = fields.requestId ?? createRequestId();
  const started = performance.now();
  try {
    const result = await run(requestId);
    logInfo(fields.operation ?? "request.completed", {
      ...fields,
      requestId,
      durationMs: Math.round(performance.now() - started),
      status: fields.status ?? 200
    });
    return result;
  } catch (error) {
    logError(fields.operation ?? "request.failed", {
      ...fields,
      requestId,
      durationMs: Math.round(performance.now() - started),
      status: fields.status ?? 500,
      errorCode: error instanceof Error ? error.name : "unknown_error"
    });
    throw error;
  }
};
