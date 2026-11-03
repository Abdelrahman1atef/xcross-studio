abstract interface class DeviceHostPolicy {
  String get installCommand;
  String get preparationDeniedMessage;
  String describeTunnelFailure(List<String> recent);
  String elevatedCommand(String arguments);
  Future<String?> resolvePipx();
  Future<bool> lockdownTunnelLooksAlive();

  // studio: 002 — checked before a run's build so a stopped service fails fast.
  /// Null when the host device service (usbmuxd / Apple Mobile Device
  /// Service) accepts a connection at [usbmuxAddress] (or the host default);
  /// otherwise an explanation with an OS-specific fix.
  Future<String?> deviceServiceProblem(String? usbmuxAddress);

  // studio: 017 — where `usbmuxd` (or Apple Mobile Device Service) listens
  // when `USBMUXD_SOCKET_ADDRESS` is not set: `host:port` or a socket path.
  /// The host's default device service address.
  String get defaultDeviceServiceAddress;
}
