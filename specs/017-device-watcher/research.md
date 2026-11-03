# Research: 017

## R1 usbmuxd Listen protocol
- **Decision:** plist protocol: header `length (u32 LE, header included) | version 1 | message 8 (plist) | tag`,
  body an XML plist `{MessageType: Listen, ClientVersionString, ProgName, kLibUSBMuxVersion: 3}`. Replies: `Result
  {Number: 0}`, then `Attached {DeviceID, Properties {SerialNumber (UDID), ConnectionType USB|Network, …}}` for every
  device already connected and later ones, `Detached {DeviceID}`, `Paired {DeviceID}` (ignored).
- **Rationale:** the same protocol libimobiledevice, pymobiledevice3 and go-ios use; Apple Mobile Device Service
  on Windows speaks it on 127.0.0.1:27015.
- **Alternatives:** polling `pymobiledevice3 usbmux list` every second (a Python process per second, ~1.5 s per
  call, heavier and slower than events).

## R2 Names and iOS versions
- **Decision:** after an attach, read the list with the existing backend (`usbDevices()`), which already returns
  names and versions; a detach needs no read.
- **Rationale:** usbmux events carry no lockdown values; a lockdown session per device is what the listing does.
