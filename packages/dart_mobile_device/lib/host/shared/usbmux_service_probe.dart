// studio: 002 — host device service reachability (specs/002-quick-wins).
import 'dart:io';

/// Whether the usbmux service accepts a connection at [address].
///
/// [address] is `host:port` (TCP, e.g. Apple Mobile Device Service on
/// `127.0.0.1:27015`) or a unix socket path (optionally prefixed `unix:`),
/// the same forms `USBMUXD_SOCKET_ADDRESS` accepts. Never throws.
Future<bool> usbmuxServiceReachable(
  String address, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  try {
    final socket = await _connect(address.trim(), timeout);
    socket.destroy();
    return true;
  } on Object {
    return false;
  }
}

final _hostPort = RegExp(r'^\[?([^\[\]/]+?)\]?:(\d+)$');

Future<Socket> _connect(String address, Duration timeout) {
  final tcp = _hostPort.firstMatch(address);
  if (tcp != null) {
    return Socket.connect(tcp[1], int.parse(tcp[2]!), timeout: timeout);
  }
  final path = address.startsWith('unix:') ? address.substring(5) : address;
  return Socket.connect(
    InternetAddress(path, type: InternetAddressType.unix),
    0,
    timeout: timeout,
  );
}
