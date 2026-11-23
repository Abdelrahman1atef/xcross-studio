//! Developer Disk Image: which kind a device needs and where its files are.
//!
//! Same choice as pymobiledevice3 11.50 (`auto_mount_personalized`):
//! - iOS 27 and later: the Cryptex1 DDI, installed over `cryptexd` (needs the RSD tunnel).
//! - iOS 17 to 26: the Personalized DMG, mounted over the image mounter.
//!
//! The files come from github.com/doronz88/DeveloperDiskImage (`PersonalizedImages/...`), as in
//! pymobiledevice3. ZenLink keeps them in `%LOCALAPPDATA%\ZenLink-Next\ddi\<kind>`; a copy that
//! pymobiledevice3 already downloaded (`~\.pymobiledevice3\<kind>`) is used too.

use std::path::{Path, PathBuf};

/// Base URL of doronz88's DeveloperDiskImage repository (`PersonalizedImages`).
pub const DDI_BASE_URL: &str =
    "https://raw.githubusercontent.com/doronz88/DeveloperDiskImage/main/PersonalizedImages";

/// The DDI kind a device needs.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Kind {
    /// iOS 17 to 26.
    Personalized,
    /// iOS 27 and later.
    Cryptex,
}

impl Kind {
    /// `None` below iOS 17 (signed DMG, not supported by ZenLink's Apple Driver mode).
    pub fn for_version(product_version: &str) -> Option<Self> {
        let major: u32 = product_version.split('.').next()?.trim().parse().ok()?;
        match major {
            0..=16 => None,
            17..=26 => Some(Kind::Personalized),
            _ => Some(Kind::Cryptex),
        }
    }

    /// Folder name, the same as in the DeveloperDiskImage repository and pymobiledevice3's cache.
    pub fn folder(self) -> &'static str {
        match self {
            Kind::Personalized => "Xcode_iOS_DDI_Personalized",
            Kind::Cryptex => "Xcode_iOS_DDI_Cryptex",
        }
    }

    /// Files of this kind, relative to its folder.
    pub fn files(self) -> &'static [&'static str] {
        match self {
            Kind::Personalized => &["BuildManifest.plist", "Image.dmg", "Image.dmg.trustcache"],
            Kind::Cryptex => &[
                "BuildManifest.plist",
                "Image.dmg",
                "Image.dmg.trustcache",
                "Image.dmg.cryptex_info",
                "Image.dmg.root_hash",
            ],
        }
    }
}

/// ZenLink's local DDI cache folder (`%LOCALAPPDATA%\ZenLink-Next\ddi\<kind>`).
pub fn cache_dir(kind: Kind) -> Option<PathBuf> {
    zenlink_core::local_data_dir().map(|d| d.join("ddi").join(kind.folder()))
}

/// Folders to look in, first match wins.
pub fn search_dirs(kind: Kind) -> Vec<PathBuf> {
    let mut dirs = Vec::new();
    if let Some(dir) = cache_dir(kind) {
        dirs.push(dir);
    }
    if let Some(home) = std::env::var_os("USERPROFILE") {
        dirs.push(
            PathBuf::from(home)
                .join(".pymobiledevice3")
                .join(kind.folder()),
        );
    }
    dirs
}

/// The first folder in `dirs` that has every file of `kind`.
pub fn find(kind: Kind, dirs: &[PathBuf]) -> Option<PathBuf> {
    dirs.iter()
        .find(|d| kind.files().iter().all(|f| d.join(f).is_file()))
        .cloned()
}

/// Raw files of a found DDI folder.
pub struct Files {
    pub build_manifest: Vec<u8>,
    pub image: Vec<u8>,
    pub trustcache: Vec<u8>,
    /// Cryptex only.
    pub cryptex_info: Vec<u8>,
    /// Cryptex only.
    pub root_hash: Vec<u8>,
}

pub fn read(kind: Kind, dir: &Path) -> std::io::Result<Files> {
    let r = |name: &str| std::fs::read(dir.join(name));
    let cryptex = kind == Kind::Cryptex;
    Ok(Files {
        build_manifest: r("BuildManifest.plist")?,
        image: r("Image.dmg")?,
        trustcache: r("Image.dmg.trustcache")?,
        cryptex_info: if cryptex {
            r("Image.dmg.cryptex_info")?
        } else {
            Vec::new()
        },
        root_hash: if cryptex {
            r("Image.dmg.root_hash")?
        } else {
            Vec::new()
        },
    })
}

/// Downloads all required files for `kind` into `dest` from `doronz88/DeveloperDiskImage`.
/// Skips files that already exist and are non-empty; writes atomically via `.tmp` files so
/// interrupted downloads never leave partial files behind.
pub fn download(kind: Kind, dest: &Path) -> Result<PathBuf, String> {
    download_with(kind, dest, download_file)
}

fn download_with(
    kind: Kind,
    dest: &Path,
    mut fetch: impl FnMut(&str, &Path) -> Result<(), String>,
) -> Result<PathBuf, String> {
    std::fs::create_dir_all(dest).map_err(|e| format!("{}: {e}", dest.display()))?;
    for file in kind.files() {
        let target = dest.join(file);
        if target.metadata().map(|m| m.len() > 0).unwrap_or(false) {
            continue;
        }
        let url = format!("{DDI_BASE_URL}/{}/{file}", kind.folder());
        let tmp = dest.join(format!("{file}.{}.tmp", std::process::id()));
        log::info!("ddi: downloading {url}");
        if let Err(e) = fetch(&url, &tmp) {
            let _ = std::fs::remove_file(&tmp);
            return Err(format!("download {file}: {e}"));
        }
        if let Err(e) = std::fs::rename(&tmp, &target) {
            let _ = std::fs::remove_file(&tmp);
            return Err(format!("save {file}: {e}"));
        }
    }
    Ok(dest.to_path_buf())
}

#[cfg(windows)]
fn download_file(url: &str, dest: &Path) -> Result<(), String> {
    use std::ffi::c_void;
    use std::io::Write;
    use windows::core::{HSTRING, PCWSTR};
    use windows::Win32::Networking::WinHttp::*;

    struct Handle(*mut c_void);
    impl Drop for Handle {
        fn drop(&mut self) {
            if !self.0.is_null() {
                unsafe {
                    let _ = WinHttpCloseHandle(self.0);
                }
            }
        }
    }

    let last_error = |what: &str| format!("{what}: {}", windows::core::Error::from_thread());

    let rest = url.strip_prefix("https://").ok_or("not an https URL")?;
    let (host, path) = match rest.find('/') {
        Some(i) => (&rest[..i], &rest[i..]),
        None => (rest, "/"),
    };

    let agent = HSTRING::from(format!("ZenLink/{}", env!("CARGO_PKG_VERSION")));
    unsafe {
        let session = Handle(WinHttpOpen(
            &agent,
            WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
            PCWSTR::null(),
            PCWSTR::null(),
            0,
        ));
        if session.0.is_null() {
            return Err(last_error("WinHttpOpen"));
        }
        let protocols = (WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_2 | WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_3)
            .to_le_bytes();
        let _ = WinHttpSetOption(
            Some(session.0),
            WINHTTP_OPTION_SECURE_PROTOCOLS,
            Some(&protocols),
        );
        let _ = WinHttpSetTimeouts(session.0, 15_000, 15_000, 15_000, 120_000);

        let connect = Handle(WinHttpConnect(
            session.0,
            &HSTRING::from(host),
            INTERNET_DEFAULT_HTTPS_PORT,
            0,
        ));
        if connect.0.is_null() {
            return Err(last_error("WinHttpConnect"));
        }

        let request = Handle(WinHttpOpenRequest(
            connect.0,
            &HSTRING::from("GET"),
            &HSTRING::from(path),
            PCWSTR::null(),
            PCWSTR::null(),
            std::ptr::null(),
            WINHTTP_FLAG_SECURE,
        ));
        if request.0.is_null() {
            return Err(last_error("WinHttpOpenRequest"));
        }

        WinHttpSendRequest(request.0, None, None, 0, 0, 0)
            .map_err(|e| format!("send: {e}"))?;
        WinHttpReceiveResponse(request.0, std::ptr::null_mut())
            .map_err(|e| format!("receive: {e}"))?;

        let query_u32 = |info: u32| -> Option<u64> {
            let mut v = 0u32;
            let mut len = 4u32;
            WinHttpQueryHeaders(
                request.0,
                info | WINHTTP_QUERY_FLAG_NUMBER,
                PCWSTR::null(),
                Some((&mut v as *mut u32).cast()),
                &mut len,
                std::ptr::null_mut(),
            )
            .ok()
            .map(|_| v as u64)
        };

        let status = query_u32(WINHTTP_QUERY_STATUS_CODE).unwrap_or(0);
        if !(200..300).contains(&status) {
            return Err(format!("HTTP {status}"));
        }
        let expected_len = query_u32(WINHTTP_QUERY_CONTENT_LENGTH);

        let mut file = std::fs::File::create(dest).map_err(|e| format!("create: {e}"))?;
        let mut buf = vec![0u8; 64 * 1024];
        let mut written: u64 = 0;
        loop {
            let mut n = 0u32;
            WinHttpReadData(
                request.0,
                buf.as_mut_ptr().cast(),
                buf.len() as u32,
                &mut n,
            )
            .map_err(|e| format!("read: {e}"))?;
            if n == 0 {
                break;
            }
            file.write_all(&buf[..n as usize])
                .map_err(|e| format!("write: {e}"))?;
            written += n as u64;
        }
        file.flush().map_err(|e| format!("flush: {e}"))?;
        if written == 0 {
            return Err("empty response".into());
        }
        if let Some(expected) = expected_len {
            if written != expected {
                return Err(format!("truncated download ({written}/{expected} bytes)"));
            }
        }
    }
    Ok(())
}

#[cfg(not(windows))]
fn download_file(_url: &str, _dest: &Path) -> Result<(), String> {
    Err("automatic DDI download is only supported on Windows".into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn kind_follows_pymobiledevice3() {
        assert_eq!(Kind::for_version("16.7.10"), None);
        assert_eq!(Kind::for_version("17.0"), Some(Kind::Personalized));
        assert_eq!(Kind::for_version("26.4.1"), Some(Kind::Personalized));
        assert_eq!(Kind::for_version("27.0"), Some(Kind::Cryptex));
        assert_eq!(Kind::for_version("28.1"), Some(Kind::Cryptex));
        assert_eq!(Kind::for_version(""), None);
    }

    #[test]
    fn find_needs_every_file() {
        let base = std::env::temp_dir().join(format!("zl-ddi-{}", std::process::id()));
        let full = base.join("full");
        let part = base.join("part");
        for d in [&full, &part] {
            std::fs::create_dir_all(d).unwrap();
        }
        for f in Kind::Cryptex.files() {
            std::fs::write(full.join(f), b"x").unwrap();
        }
        std::fs::write(part.join("Image.dmg"), b"x").unwrap();
        assert_eq!(
            find(Kind::Cryptex, &[part.clone(), full.clone()]),
            Some(full.clone())
        );
        assert_eq!(find(Kind::Cryptex, &[part]), None);
        let files = read(Kind::Cryptex, &full).unwrap();
        assert_eq!(files.root_hash, b"x");
        std::fs::remove_dir_all(base).unwrap();
    }

    #[test]
    fn download_with_fetches_missing_and_cleans_tmp_on_error() {
        let base = std::env::temp_dir().join(format!("zl-ddi-dl-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&base);

        // Pre-populate one file to verify it is skipped.
        std::fs::create_dir_all(&base).unwrap();
        std::fs::write(base.join("BuildManifest.plist"), b"cached").unwrap();

        let mut seen = Vec::new();
        let res = download_with(Kind::Personalized, &base, |url, tmp| {
            seen.push(url.to_string());
            std::fs::write(tmp, b"downloaded")
                .map_err(|e| format!("write: {e}"))
        });
        assert!(res.is_ok(), "{res:?}");
        assert_eq!(
            seen,
            vec![
                format!("{DDI_BASE_URL}/Xcode_iOS_DDI_Personalized/Image.dmg"),
                format!("{DDI_BASE_URL}/Xcode_iOS_DDI_Personalized/Image.dmg.trustcache"),
            ]
        );
        assert_eq!(std::fs::read(base.join("BuildManifest.plist")).unwrap(), b"cached");
        assert!(find(Kind::Personalized, &[base.clone()]).is_some());

        // Simulate failure on Cryptex: partial .tmp must be cleaned up.
        let fail_dir = base.join("fail");
        let err = download_with(Kind::Cryptex, &fail_dir, |url, tmp| {
            std::fs::write(tmp, b"partial").unwrap();
            if url.ends_with("Image.dmg") {
                return Err("network error".into());
            }
            Ok(())
        });
        assert!(err.is_err());
        assert!(find(Kind::Cryptex, &[fail_dir.clone()]).is_none());
        let leftovers: Vec<_> = std::fs::read_dir(&fail_dir)
            .unwrap()
            .filter_map(|e| e.ok())
            .filter(|e| e.file_name().to_string_lossy().ends_with(".tmp"))
            .collect();
        assert!(leftovers.is_empty(), "leftover tmp files: {leftovers:?}");

        std::fs::remove_dir_all(base).unwrap();
    }
}
