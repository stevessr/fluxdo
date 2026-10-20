import { mount, signal, Text, View } from "nsh";
import { readNativeBootstrapStatus } from "../host_native_transport";

// Isolated mixed Rust/TSX probe. Do NOT mount this from nsh/App.tsx until
// the upstream NSH 0.1.1 generated-cli dependency issue is resolved.
function Probe() {
  const status = signal("Checking Rust export…");
  void readNativeBootstrapStatus().then(
    () => status.set("Native Rust bootstrap connected; all private capabilities disabled"),
    () => status.set("Native transport not yet available"),
  );
  return <View style={{ padding: 18 }}><Text>{status()}</Text></View>;
}
mount(Probe);
