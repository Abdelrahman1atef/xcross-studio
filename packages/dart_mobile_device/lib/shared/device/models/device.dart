import 'package:meta/meta.dart';

/// Which devices to search for.
enum DeviceSearchMode { all, usb, wifi }

/// Which discovery mechanism produced a [Device].
enum DeviceSource {
  /// usbmuxd (`pymobiledevice3 usbmux list`).
  usbmux,

  /// tunneld's active-tunnel list (already has an RSD tunnel).
  tunneld,
}

/// How a device is connected.
enum ConnectionType {
  usb,
  wifi;

  static ConnectionType parse(String raw) {
    final v = raw.toLowerCase();
    // pymobiledevice3 reports wireless devices as `Network`.
    return (v == 'wifi' || v == 'network')
        ? ConnectionType.wifi
        : ConnectionType.usb;
  }
}

/// A connected iOS device.
@immutable
final class Device {
  const Device({
    required this.name,
    required this.udid,
    required this.type,
    this.source = DeviceSource.usbmux,
    this.osVersion,
  });

  /// Human-readable device name.
  final String name;

  /// Unique device identifier.
  final String udid;

  /// Connection type (USB or Wi-Fi).
  final ConnectionType type;

  /// Discovery mechanism that produced this entry.
  final DeviceSource source;

  // studio: 002 — lets the run precheck gate the iOS version without a second
  // pymobiledevice3 call.
  /// `ProductVersion` reported by the listing (e.g. `16.7.10`), when known.
  final String? osVersion;

  @override
  String toString() => '$name [${type.name}]: $udid';
}
