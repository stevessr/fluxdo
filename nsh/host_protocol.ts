/**
 * Versioned read-only NSH -> Rust/Native Host contract.
 * This is only the TSX protocol boundary. There is NO native transport binding yet.
 * Host must independently enforce user identity, permissions and account isolation.
 * Never put Cookie, API tokens or raw session materials in command parameters.
 */
export const HOST_PROTOCOL_VERSION = 1 as const;
export const MAX_REQUEST_BYTES = 16 * 1024;
export const MAX_RESPONSE_BYTES = 512 * 1024;

export type HostReadCommand =
  | { method: "capabilities.read"; params: Record<string, never> }
  | { method: "feed.list"; params: { kind: "latest" | "top"; cursor?: string } }
  | { method: "topic.read"; params: { topicId: number; postNumber?: number } }
  | { method: "search.query"; params: { term: string; page: number } };

export interface HostRequest {
  protocol: typeof HOST_PROTOCOL_VERSION;
  id: number;
  method: HostReadCommand["method"];
  params: HostReadCommand["params"];
}

export interface HostTransport {
  invoke(request: HostRequest): Promise<unknown>;
}

export type HostFailureCode =
  | "invalid_command" | "invalid_reply" | "oversized_frame"
  | "transport_error" | "superseded" | "unauthorized"
  | "unavailable" | "rate_limited" | "internal";

export class HostProtocolError extends Error {
  constructor(readonly code: HostFailureCode) {
    super("Host Bridge: " + code);
    this.name = "HostProtocolError";
  }
}

function isRecord(input: unknown): input is Record<string, unknown> {
  return typeof input === "object" && input !== null && !Array.isArray(input);
}
function isPositiveInteger(value: unknown, max: number): value is number {
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0 && value <= max;
}
function fields(input: Record<string, unknown>, allowed: string[]): boolean {
  return Object.keys(input).every((name) => allowed.includes(name));
}

/**
 * Validate at runtime, not only at the TS type level. In particular reject
 * surplus keys so an accidental token field cannot be forwarded to Host.
 */
export function validateHostCommand(command: unknown): asserts command is HostReadCommand {
  if (!isRecord(command) || !isRecord(command.params) ||
      typeof command.method !== "string") {
    throw new HostProtocolError("invalid_command");
  }
  const p = command.params;
  switch (command.method) {
    case "capabilities.read":
      if (Object.keys(p).length === 0) return;
      break;
    case "feed.list":
      if (fields(p, ["kind", "cursor"]) &&
          (p.kind === "latest" || p.kind === "top") &&
          (p.cursor === undefined ||
            (typeof p.cursor === "string" && p.cursor.length > 0 &&
              p.cursor.length <= 2048 && p.cursor.startsWith("/") &&
              !p.cursor.startsWith("//")))) return;
      break;
    case "topic.read":
      if (fields(p, ["topicId", "postNumber"]) &&
          isPositiveInteger(p.topicId, Number.MAX_SAFE_INTEGER) &&
          (p.postNumber === undefined || isPositiveInteger(p.postNumber, 10000000))) return;
      break;
    case "search.query":
      if (fields(p, ["term", "page"]) &&
          typeof p.term === "string" && p.term.trim().length >= 2 &&
          p.term.length <= 120 && !/[\u0000-\u001f\u007f]/.test(p.term) &&
          isPositiveInteger(p.page, 50)) return;
      break;
    default:
      break;
  }
  throw new HostProtocolError("invalid_command");
}

function utf8ByteLength(value: string): number {
  let size = 0;
  for (let i = 0; i < value.length; i++) {
    const c = value.charCodeAt(i);
    if (c < 0x80) size++;
    else if (c < 0x800) size += 2;
    else if (c >= 0xd800 && c <= 0xdbff && i + 1 < value.length &&
             value.charCodeAt(i + 1) >= 0xdc00 && value.charCodeAt(i + 1) <= 0xdfff) {
      size += 4;
      i++;
    } else size += 3;
  }
  return size;
}

function checkFrameSize(value: unknown, limit: number): void {
  let serialized: string | undefined;
  try { serialized = JSON.stringify(value); } catch {
    throw new HostProtocolError("invalid_reply");
  }
  if (typeof serialized !== "string") throw new HostProtocolError("invalid_reply");
  if (utf8ByteLength(serialized) > limit) throw new HostProtocolError("oversized_frame");
}

const allowedErrors = new Set<HostFailureCode>([
  "unauthorized", "unavailable", "rate_limited", "internal",
]);

/**
 * A local generation gate; not an authorization boundary.
 * Native Host must check its own session epoch and apply permissions.
 */
export class HostBridge {
  private nextId = 0;
  private generation = 0;

  constructor(private readonly transport: HostTransport) {}

  invalidatePending(): void { this.generation++; }

  async invoke(command: HostReadCommand): Promise<unknown> {
    validateHostCommand(command);
    if (this.nextId >= Number.MAX_SAFE_INTEGER) throw new HostProtocolError("invalid_command");
    const frame: HostRequest = {
      protocol: HOST_PROTOCOL_VERSION,
      id: ++this.nextId,
      method: command.method,
      params: command.params,
    };
    checkFrameSize(frame, MAX_REQUEST_BYTES);
    const generation = this.generation;
    let result: unknown;
    try {
      result = await this.transport.invoke(frame);
    } catch (error) {
      // Preserve only a known local "unavailable" error; never surface arbitrary
      // native exception strings that might contain credentials.
      if (generation !== this.generation) throw new HostProtocolError("superseded");
      if (error instanceof HostProtocolError && error.code === "unavailable") throw error;
      throw new HostProtocolError("transport_error");
    }
    if (generation !== this.generation) throw new HostProtocolError("superseded");
    checkFrameSize(result, MAX_RESPONSE_BYTES);
    if (!isRecord(result) || result.protocol !== HOST_PROTOCOL_VERSION ||
        result.id !== frame.id || typeof result.ok !== "boolean") {
      throw new HostProtocolError("invalid_reply");
    }
    if (result.ok === false) {
      const code = isRecord(result.error) ? result.error.code : null;
      throw new HostProtocolError(allowedErrors.has(code as HostFailureCode)
        ? code as HostFailureCode : "internal");
    }
    if (!("data" in result)) throw new HostProtocolError("invalid_reply");
    return result.data;
  }
}

/** Safe default until a vetted NSH-native Rust/Platform transport is installed. */
export const unavailableHostTransport: HostTransport = {
  async invoke(): Promise<never> { throw new HostProtocolError("unavailable"); },
};
