//! Smooth mode on Windows: which driver an iPhone uses, and switching it (spec 048, E4).
//!
//! The switch itself is ZenLink's `usb_filter.ps1` (unchanged, `vendor/zenlink-drivers/tools`),
//! run elevated and hidden after the user agreed in Studio. It changes only the chosen iPhone,
//! keeps a backup and rolls back on failure; its JSON result is passed on.

use std::path::{Path, PathBuf};
use std::process::Command;

use serde_json::{json, Value};

/// One Apple USB device node (the composite parent, `USB\VID_05AC&PID_12xx\<serial>`).
#[derive(Debug, Clone, PartialEq)]
pub struct Node {
    pub instance: String,
    pub name: String,
    pub service: String,
}

impl Node {
    /// The USB serial (the iPhone's UDID without dashes), from the instance id.
    pub fn serial(&self) -> String {
        normalize(self.instance.rsplit('\\').next().unwrap_or(""))
    }

    /// `smooth` (libusb0: QuickTime capture), `apple` (Apple's driver), or `other`.
    pub fn state(&self) -> &'static str {
        match self.service.to_ascii_lowercase().as_str() {
            "libusb0" => "smooth",
            "usbccgp" => "apple",
            _ => "other",
        }
    }
}

pub fn normalize(serial: &str) -> String {
    serial.replace('-', "").to_uppercase()
}

/// Parses the status script's JSON (an array, a single object, or nothing).
pub fn parse_nodes(text: &str) -> Vec<Node> {
    let text = text.trim().trim_start_matches('\u{feff}');
    if text.is_empty() {
        return Vec::new();
    }
    let value: Value = serde_json::from_str(text).unwrap_or(Value::Null);
    let items = match value {
        Value::Array(a) => a,
        Value::Object(_) => vec![value],
        _ => Vec::new(),
    };
    items
        .iter()
        .filter_map(|v| {
            let instance = v.get("instance")?.as_str()?.to_string();
            Some(Node {
                instance,
                name: v.get("name").and_then(Value::as_str).unwrap_or("").to_string(),
                service: v.get("service").and_then(Value::as_str).unwrap_or("").to_string(),
            })
        })
        .collect()
}

pub fn find<'a>(nodes: &'a [Node], serial: &str) -> Option<&'a Node> {
    let want = normalize(serial);
    nodes.iter().find(|n| n.serial() == want)
}

const STATUS_SCRIPT: &str = r#"$ErrorActionPreference = 'SilentlyContinue'
$nodes = @(Get-PnpDevice -PresentOnly | Where-Object { $_.InstanceId -match '^USB\\VID_05AC&PID_12[0-9A-F]{2}\\[^\\&]+$' } | ForEach-Object {
  [pscustomobject]@{ instance = $_.InstanceId; name = $_.FriendlyName; service = (Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName 'DEVPKEY_Device_Service').Data }
})
ConvertTo-Json -InputObject $nodes -Compress"#;

/// The present Apple device nodes and their drivers (no admin rights needed).
pub fn nodes() -> Result<Vec<Node>, String> {
    let out = Command::new("powershell")
        .args(["-NoProfile", "-NonInteractive", "-Command", STATUS_SCRIPT])
        .output()
        .map_err(|e| format!("PowerShell could not start: {e}"))?;
    Ok(parse_nodes(&String::from_utf8_lossy(&out.stdout)))
}

/// Where `tools/usb_filter.ps1` lives: `XCROSS_SCREEN_DRIVERS`, else `screen-drivers` next to
/// this program, else the repository's `vendor/zenlink-drivers` (development builds).
pub fn drivers_dir() -> Option<PathBuf> {
    if let Some(dir) = std::env::var_os("XCROSS_SCREEN_DRIVERS") {
        let dir = PathBuf::from(dir);
        return script_in(&dir).then_some(dir);
    }
    let exe = std::env::current_exe().ok()?;
    let here = exe.parent()?;
    [here.join("screen-drivers"), here.join("../../vendor/zenlink-drivers")]
        .into_iter()
        .find(|d| script_in(d))
}

fn script_in(dir: &Path) -> bool {
    dir.join("tools").join("usb_filter.ps1").is_file()
}

/// PowerShell single-quoted literal.
fn ps_quote(s: &str) -> String {
    format!("'{}'", s.replace('\'', "''"))
}

/// The elevated, hidden run of the switch script; exit 1223 when Windows' prompt was declined.
pub fn elevated_command(script: &Path, action: &str, instance: &str, result: &Path) -> String {
    let arg = |s: &str| ps_quote(&format!("\"{s}\""));
    format!(
        "try {{ $p = Start-Process -FilePath powershell -Verb RunAs -Wait -PassThru -WindowStyle Hidden \
         -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',{},'-Action',{},'-InstanceId',{},'-ResultPath',{}); \
         exit $p.ExitCode }} catch {{ exit 1223 }}",
        arg(&script.display().to_string()),
        ps_quote(action),
        arg(instance),
        arg(&result.display().to_string()),
    )
}

/// The switch script's result file as an event body.
pub fn parse_result(text: &str) -> Value {
    let v: Value = serde_json::from_str(text.trim().trim_start_matches('\u{feff}')).unwrap_or(Value::Null);
    let message = v.get("message").and_then(Value::as_str).unwrap_or("").to_string();
    json!({
        "ok": v.get("ok").and_then(Value::as_bool).unwrap_or(false),
        "message": message,
        "rolledBack": v.get("rolledBack").and_then(Value::as_bool).unwrap_or(false),
        "reboot": v.get("reboot").and_then(Value::as_bool).unwrap_or(false),
        "replug": message.to_lowercase().contains("plug it in again"),
    })
}

/// Runs `bind` (Smooth mode on) or `restore` (Apple driver back) for [serial].
pub fn change(serial: &str, enable: bool) -> Value {
    let action = if enable { "enable" } else { "restore" };
    let base = json!({ "type": "screen_driver_change", "action": action, "serial": normalize(serial) });
    let fail = |message: String| {
        let mut v = base.clone();
        v["ok"] = json!(false);
        v["message"] = json!(message);
        v
    };
    let Some(dir) = drivers_dir() else {
        return fail("The screen driver files are missing from this engine. Update the engine.".into());
    };
    let nodes = match nodes() {
        Ok(n) => n,
        Err(e) => return fail(e),
    };
    let Some(node) = find(&nodes, serial) else {
        return fail("This iPhone is not plugged in by USB.".into());
    };
    if enable && node.state() == "smooth" || !enable && node.state() == "apple" {
        let mut v = base.clone();
        v["ok"] = json!(true);
        v["message"] = json!("Already done.");
        return v;
    }
    let result = std::env::temp_dir().join(format!("xcross-screen-driver-{}.json", uuid::Uuid::new_v4().simple()));
    let script = dir.join("tools").join("usb_filter.ps1");
    let cmd = elevated_command(&script, if enable { "bind" } else { "restore" }, &node.instance, &result);
    let status = Command::new("powershell").args(["-NoProfile", "-NonInteractive", "-Command", &cmd]).status();
    let code = status.ok().and_then(|s| s.code()).unwrap_or(-1);
    let text = std::fs::read_to_string(&result).unwrap_or_default();
    let _ = std::fs::remove_file(&result);
    if code == 1223 && text.is_empty() {
        return fail("Windows permission was not given. Nothing was changed.".into());
    }
    if text.is_empty() {
        return fail(format!("The driver switch did not report a result (exit {code})."));
    }
    let mut v = base;
    if let (Value::Object(dst), Value::Object(src)) = (&mut v, parse_result(&text)) {
        dst.extend(src);
    }
    v
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nodes_parse_from_array_object_and_nothing() {
        let a = r#"[{"instance":"USB\\VID_05AC&PID_12A8\\388855A5602B2D44E545EC8B4C5E45B95CC1EA47","name":"iPhone (ZenLink USB Direct)","service":"libusb0"}]"#;
        let n = parse_nodes(a);
        assert_eq!(n.len(), 1);
        assert_eq!(n[0].serial(), "388855A5602B2D44E545EC8B4C5E45B95CC1EA47");
        assert_eq!(n[0].state(), "smooth");
        let o = "\u{feff}{\"instance\":\"USB\\\\VID_05AC&PID_12A8\\\\00008020-001A2B3C4D5E6F70\",\"name\":\"Apple Mobile Device USB Composite Device\",\"service\":\"usbccgp\"}";
        let n = parse_nodes(o);
        assert_eq!(n[0].state(), "apple");
        assert_eq!(n[0].serial(), "00008020001A2B3C4D5E6F70");
        assert!(parse_nodes("").is_empty());
        assert!(parse_nodes("[]").is_empty());
        assert!(parse_nodes("not json").is_empty());
    }

    #[test]
    fn find_matches_udid_with_or_without_dashes_and_case() {
        let n = parse_nodes(r#"[{"instance":"USB\\VID_05AC&PID_12A8\\00008020001A2B3C4D5E6F70","name":"x","service":"usbccgp"}]"#);
        assert!(find(&n, "00008020-001a2b3c4d5e6f70").is_some());
        assert!(find(&n, "OTHER").is_none());
    }

    #[test]
    fn elevated_command_quotes_paths_and_reports_a_declined_prompt() {
        let cmd = elevated_command(
            Path::new(r"C:\Program Files\x\usb_filter.ps1"),
            "bind",
            r"USB\VID_05AC&PID_12A8\ABC",
            Path::new(r"C:\Temp\r's.json"),
        );
        assert!(cmd.contains(r#"'"C:\Program Files\x\usb_filter.ps1"'"#));
        assert!(cmd.contains(r#"'"USB\VID_05AC&PID_12A8\ABC"'"#));
        assert!(cmd.contains(r#"'"C:\Temp\r''s.json"'"#), "single quotes doubled: {cmd}");
        assert!(cmd.contains("-Verb RunAs") && cmd.contains("-WindowStyle Hidden"));
        assert!(cmd.contains("exit 1223"));
    }

    #[test]
    fn result_file_becomes_the_event_body() {
        let r = parse_result("\u{feff}{\"ok\":true,\"message\":\"Apple driver restored. Unplug the cable and plug it in again.\",\"rolledBack\":false,\"reboot\":false}");
        assert_eq!(r["ok"], true);
        assert_eq!(r["replug"], true);
        let r = parse_result("{\"ok\":false,\"message\":\"No driver package\",\"rolledBack\":true}");
        assert_eq!(r["ok"], false);
        assert_eq!(r["rolledBack"], true);
        assert_eq!(r["replug"], false);
    }
}
