//! Stand-in for ZenLink's `zenlink-core` (GPL-3.0): only the two functions `zenlink-apple`
//! calls. `quick_ack` is ZenLink's code (v2.5.17); `local_data_dir` points at xcross's
//! own folder instead of ZenLink's.

use std::path::PathBuf;

/// Where `zenlink-apple` keeps downloaded developer disk images and similar data.
/// xcross: `%LOCALAPPDATA%\xcross\screen` (Windows) or `$XDG_DATA_HOME/xcross/screen`.
pub fn local_data_dir() -> Option<PathBuf> {
    if let Some(base) = std::env::var_os("LOCALAPPDATA") {
        return Some(PathBuf::from(base).join("xcross").join("screen"));
    }
    if let Some(base) = std::env::var_os("XDG_DATA_HOME") {
        return Some(PathBuf::from(base).join("xcross").join("screen"));
    }
    std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".local/share/xcross/screen"))
}

/// Acknowledge every TCP segment at once (lower delay for the Wi-Fi tunnel). ZenLink v2.5.17.
#[cfg(windows)]
pub fn quick_ack(s: &impl std::os::windows::io::AsRawSocket) {
    use windows::Win32::Networking::WinSock::{WSAIoctl, SIO_TCP_SET_ACK_FREQUENCY, SOCKET};
    let freq: u32 = 1;
    let mut n = 0u32;
    // SAFETY: a valid socket handle and a 4-byte input buffer that outlives the call.
    let r = unsafe {
        WSAIoctl(
            SOCKET(s.as_raw_socket() as usize),
            SIO_TCP_SET_ACK_FREQUENCY,
            Some(&freq as *const u32 as _),
            4,
            None,
            0,
            &mut n,
            None,
            None,
        )
    };
    if r != 0 {
        log::info!("quick ACK not available on this socket");
    }
}

#[cfg(not(windows))]
pub fn quick_ack<T>(_: &T) {}
