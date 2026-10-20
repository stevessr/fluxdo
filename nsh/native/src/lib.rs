//! Minimal REAL NSH Rust native module (not an authenticated Discourse service).
//! No credentials, account storage, network or write capability are available.
use nsh_core::ui::prelude::*;
use serde_json::{json, Value};

#[native_module("fluxdo/native")]
fn native(registry: &mut Registry) {
    registry.module::<FluxdoHost>();
}

/// Read-only bootstrap handshake; returns bounded versioned JSON frames.
pub struct FluxdoHost;

#[module]
impl FluxdoHost {
    /// A Rust-backed protocol invocation, not an HTTP/credential tunnel.
    pub fn invoke(frame_json: String) -> String {
        invoke_frame(&frame_json)
    }
}

fn invoke_frame(raw: &str) -> String {
    if raw.len() > 16 * 1024 {
        return error_reply(0);
    }
    let Ok(frame) = serde_json::from_str::<Value>(raw) else {
        return error_reply(0);
    };
    let Some(fields) = frame.as_object() else {
        return error_reply(0);
    };
    let id = fields.get("id").and_then(Value::as_u64)
        .filter(|n| *n > 0 && *n <= 9_007_199_254_740_991).unwrap_or(0);
    if id == 0 || fields.len() != 4 ||
        fields.get("protocol").and_then(Value::as_u64) != Some(1) ||
        fields.get("method").and_then(Value::as_str) != Some("capabilities.read") ||
        fields.get("params").and_then(Value::as_object).is_none_or(|p| !p.is_empty()) {
        return error_reply(id);
    }
    json!({
        "protocol": 1, "id": id, "ok": true,
        "data": {"mode": "native_bootstrap", "protocol": 1,
            "nativeModule": true, "coreConnected": false,
            "authenticatedRead": false, "multiAccount": false,
            "writes": false, "chat": false}
    }).to_string()
}

fn error_reply(id: u64) -> String {
    json!({"protocol":1,"id":id,"ok":false,"error":{"code":"invalid_command"}}).to_string()
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn handshake_is_non_privileged() {
        let value: Value = serde_json::from_str(&invoke_frame(
            r#"{"protocol":1,"id":9,"method":"capabilities.read","params":{}}"#
        )).unwrap();
        assert_eq!(value["id"], 9);
        assert_eq!(value["ok"], true);
        assert_eq!(value["data"]["nativeModule"], true);
        assert_eq!(value["data"]["multiAccount"], false);
        assert_eq!(value["data"]["authenticatedRead"], false);
        assert_eq!(value["data"]["writes"], false);
    }

    #[test]
    fn malformed_commands_are_rejected_without_echoing_secrets() {
        for payload in [
            r#"{"protocol":1,"id":1,"method":"account.login","params":{}}"#,
            r#"{"protocol":1,"id":2,"method":"capabilities.read","params":{"token":"secret"}}"#,
            r#"{"protocol":1,"id":3,"method":"capabilities.read","params":{},"cookie":"secret"}"#,
            r#"{"protocol":2,"id":4,"method":"capabilities.read","params":{}}"#,
            r#"{"protocol":1,"id":5,"method":"feed.list","params":{"kind":"latest"}}"#,
        ] {
            let value: Value = serde_json::from_str(&invoke_frame(payload)).unwrap();
            assert_eq!(value["ok"], false);
            assert!(!value.to_string().contains("secret"));
        }
    }
}
