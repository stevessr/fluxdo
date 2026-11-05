/**
 * Genuine NSH Rust module adapter. No fallback to global JS injection.
 * Only a non-privileged capability handshake is supported by the native core.
 */
import { FluxdoHost } from "fluxdo/native";
import { HostBridge, HostProtocolError, MAX_RESPONSE_BYTES, type HostTransport } from "./host_protocol";

const transport: HostTransport = {
  async invoke(frame) {
    const raw = FluxdoHost.invoke(JSON.stringify(frame));
    if (typeof raw !== "string" || raw.length > MAX_RESPONSE_BYTES) {
      throw new HostProtocolError("invalid_reply");
    }
    try { return JSON.parse(raw) as unknown; }
    catch { throw new HostProtocolError("invalid_reply"); }
  },
};
export const nativeHostBridge = new HostBridge(transport);

export async function readNativeBootstrapStatus(): Promise<boolean> {
  const response = await nativeHostBridge.invoke({method:"capabilities.read",params:{}});
  if (!response || typeof response !== "object" || Array.isArray(response)) {
    throw new HostProtocolError("invalid_reply");
  }
  const data = response as Record<string, unknown>;
  if (data.mode !== "native_bootstrap" || data.protocol !== 1 ||
    data.nativeModule !== true || data.coreConnected !== false ||
    data.authenticatedRead !== false || data.multiAccount !== false ||
    data.writes !== false || data.chat !== false) {
    throw new HostProtocolError("invalid_reply");
  }
  return true;
}
