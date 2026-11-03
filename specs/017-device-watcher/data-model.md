# Data model: 017

- **UsbmuxEvent**: `UsbmuxAttached {deviceId: int, udid: String, connectionType: "USB"|"Network"}`,
  `UsbmuxDetached {deviceId: int}`.
- **Snapshot event** `{"v":1,"type":"devices","devices":[{"udid","name","osVersion","connection"}]}`.
- **Notice** `{"v":1,"type":"notice","message":"The device service is not reachable; retrying…"}`.
- **GUI** `DeviceController {devices, serviceDown, watching}`.
