# Run over Wi-Fi

[← xcross README](../../README.md) · [All guides](README.md)

Prepare the wireless pairing and RSD tunnel first:

```sh
xcross tunnel --wifi
```

The command automatically follows this order:

1. **USB connected:** pairs RemotePairing through the iPhone's trusted lockdown connection, enables Wi-Fi connections, opens the RSD tunnel, and mounts the Developer Disk Image. Unplug USB when it reports that the device is ready.
2. **No USB, saved pairing available:** tries to reconnect to the saved wireless device.
3. **Saved device does not reconnect:** starts a fresh, suffixed `remote pair-host` advertisement so iOS does not reuse the stale entry.
4. **No USB and no saved pairing:** starts `remote pair-host` immediately.

Then run the app over Wi-Fi:

```sh
xcross flutter run --wifi
```

Device-initiated pairing without USB requires **iOS 27 or later**. When prompted, open **Settings > Privacy and Security > Developer Mode > Paired Devices > Other Devices**, tap the exact `xcross-...` name printed in the terminal, and enter the six-digit code. On iOS 17 through 26, connect USB once and run `xcross tunnel --wifi` to create the wireless pairing through lockdown.

Keep the iPhone unlocked and on the same local subnet during setup. Wireless discovery uses mDNS on UDP port 5353, so guest-network isolation, VPN routing, firewalls, NAT, and unbridged VM or WSL networking can block it. For diagnostics, put the verbose flag at the end:

```sh
xcross tunnel --wifi -v
```

Without an explicit transport flag, `xcross flutter run` prefers a locally attached USB device and falls back to Wi-Fi when no USB device is available. Use `--wifi` or `--usb` to force one transport.

See the full [Wi-Fi setup and troubleshooting guide](https://xcross.sh/docs/wireless).
