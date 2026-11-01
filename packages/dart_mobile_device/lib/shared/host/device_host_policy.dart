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
}
