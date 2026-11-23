//! H.264 framing for players: the device sends avcC + length-prefixed access units; decoders
//! fed from a byte stream want Annex-B (start codes).

const START: [u8; 4] = [0, 0, 0, 1];

/// SPS and PPS of an avcC record as Annex-B, or `None` when the record is malformed.
pub fn avcc_to_annexb(avcc: &[u8]) -> Option<Vec<u8>> {
    if avcc.len() < 7 || avcc[0] != 1 {
        return None;
    }
    let mut out = Vec::new();
    let mut pos = 5;
    let sps_count = (avcc[pos] & 0x1F) as usize;
    pos += 1;
    for _ in 0..sps_count {
        pos = copy_unit(avcc, pos, &mut out)?;
    }
    let pps_count = *avcc.get(pos)? as usize;
    pos += 1;
    for _ in 0..pps_count {
        pos = copy_unit(avcc, pos, &mut out)?;
    }
    Some(out)
}

fn copy_unit(src: &[u8], pos: usize, out: &mut Vec<u8>) -> Option<usize> {
    let len = u16::from_be_bytes([*src.get(pos)?, *src.get(pos + 1)?]) as usize;
    let unit = src.get(pos + 2..pos + 2 + len)?;
    out.extend_from_slice(&START);
    out.extend_from_slice(unit);
    Some(pos + 2 + len)
}

/// A length-prefixed (4-byte) access unit as Annex-B, and whether it holds an IDR slice.
pub fn au_to_annexb(au: &[u8]) -> Option<(Vec<u8>, bool)> {
    let mut out = Vec::with_capacity(au.len() + 16);
    let mut pos = 0;
    let mut idr = false;
    while pos < au.len() {
        let size = u32::from_be_bytes(au.get(pos..pos + 4)?.try_into().ok()?) as usize;
        let nal = au.get(pos + 4..pos + 4 + size)?;
        if nal.is_empty() {
            return None;
        }
        if nal[0] & 0x1F == 5 {
            idr = true;
        }
        out.extend_from_slice(&START);
        out.extend_from_slice(nal);
        pos += 4 + size;
    }
    Some((out, idr))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn avcc_becomes_sps_and_pps_with_start_codes() {
        // version 1, profile/compat/level, 4-byte lengths, 1 SPS (3 bytes), 1 PPS (2 bytes)
        let avcc = [1, 0x64, 0, 0x28, 0xFF, 0xE1, 0, 3, 0x67, 0xAA, 0xBB, 1, 0, 2, 0x68, 0xCC];
        assert_eq!(
            avcc_to_annexb(&avcc).unwrap(),
            vec![0, 0, 0, 1, 0x67, 0xAA, 0xBB, 0, 0, 0, 1, 0x68, 0xCC]
        );
    }

    #[test]
    fn malformed_avcc_is_refused() {
        assert!(avcc_to_annexb(&[0, 1, 2]).is_none());
        assert!(avcc_to_annexb(&[1, 0x64, 0, 0x28, 0xFF, 0xE1, 0, 9, 0x67]).is_none());
    }

    #[test]
    fn access_unit_gets_start_codes_and_idr_flag() {
        let au = [0, 0, 0, 2, 0x65, 0x11, 0, 0, 0, 1, 0x06];
        let (out, idr) = au_to_annexb(&au).unwrap();
        assert_eq!(out, vec![0, 0, 0, 1, 0x65, 0x11, 0, 0, 0, 1, 0x06]);
        assert!(idr);
        let (_, idr) = au_to_annexb(&[0, 0, 0, 1, 0x41]).unwrap();
        assert!(!idr);
    }

    #[test]
    fn truncated_access_unit_is_refused() {
        assert!(au_to_annexb(&[0, 0, 0, 9, 0x65]).is_none());
        assert!(au_to_annexb(&[0, 0, 0, 0]).is_none());
    }
}
