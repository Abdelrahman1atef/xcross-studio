// studio: 017 — a live device list from usbmuxd events
// (specs/017-device-watcher, AC-017-2, AC-017-3).
import 'dart:async';

import 'package:dart_mobile_device/host/shared/usbmux_listen.dart';
import 'package:dart_mobile_device/shared/device/models/device.dart';
import 'package:meta/meta.dart';

/// Keeps the list of USB iPhones up to date from usbmuxd's `Listen` events:
/// a detach drops the device at once, an attach re-reads names and iOS
/// versions with [list] (bursts within [debounce] are merged), and an
/// unreachable service is reported once and retried every [retry].
@internal
final class DeviceWatch {
  DeviceWatch({
    required this.listen,
    required this.list,
    required this.onSnapshot,
    required this.onNotice,
    this.debounce = const Duration(milliseconds: 300),
    this.retry = const Duration(seconds: 2),
  });

  /// A new `Listen` session.
  final Stream<UsbmuxEvent> Function() listen;

  /// The connected USB devices with names and versions.
  final Future<List<Device>> Function() list;

  /// Called with the full list at start and after every change.
  final void Function(List<Device> devices) onSnapshot;

  /// Called when the device service is lost (once per outage).
  final void Function(String message) onNotice;

  final Duration debounce;
  final Duration retry;

  /// The message for an outage.
  static const unreachable = 'The device service is not reachable; retrying…';

  List<Device>? _last;
  final Map<int, String> _udids = {};

  /// Runs until [stop] completes.
  Future<void> run(Future<void> stop) async {
    var stopped = false;
    unawaited(stop.then((_) => stopped = true));
    var down = false;
    while (!stopped) {
      final session = DeviceWatchSession(this);
      final ended = Completer<void>();
      final subscription = listen().listen(
        session.handle,
        onError: (Object _) {
          if (!ended.isCompleted) ended.complete();
        },
        onDone: () {
          if (!ended.isCompleted) ended.complete();
        },
      );
      // A first read as soon as the service answers; it also covers a
      // computer with no device, which gets no Attached message at all.
      final connected = session.relistSoon(Duration.zero);
      await Future.any([ended.future, stop]);
      session.close();
      await subscription.cancel();
      await connected.catchError((Object _) {});
      if (stopped) break;
      if (!down) {
        down = true;
        onNotice(unreachable);
        _emit(const []);
      }
      await Future.any([Future<void>.delayed(retry), stop]);
      if (session.everConnected) down = false;
    }
  }

  void _emit(List<Device> devices) {
    final last = _last;
    if (last != null && _same(last, devices)) return;
    _last = List.unmodifiable(devices);
    onSnapshot(_last!);
  }

  static bool _same(List<Device> a, List<Device> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].udid != b[i].udid ||
          a[i].name != b[i].name ||
          a[i].osVersion != b[i].osVersion) {
        return false;
      }
    }
    return true;
  }

  /// UDIDs compare without dashes and case, as `PymdDevices` does.
  @visibleForTesting
  static String normalize(String udid) =>
      udid.replaceAll('-', '').toUpperCase();
}

/// One `Listen` session's state.
@internal
final class DeviceWatchSession {
  DeviceWatchSession(this.watch);

  final DeviceWatch watch;
  Timer? _timer;
  Future<void>? _reading;
  bool _again = false;
  bool _closed = false;
  bool everConnected = false;

  void handle(UsbmuxEvent event) {
    everConnected = true;
    switch (event) {
      case UsbmuxAttached(isUsb: false):
        return;
      case UsbmuxAttached(:final deviceId, :final udid):
        watch._udids[deviceId] = udid;
        unawaited(relistSoon(watch.debounce));
      case UsbmuxDetached(:final deviceId):
        final udid = watch._udids.remove(deviceId);
        final last = watch._last;
        if (udid == null || last == null) return;
        final gone = DeviceWatch.normalize(udid);
        watch._emit([
          for (final device in last)
            if (DeviceWatch.normalize(device.udid) != gone) device,
        ]);
    }
  }

  /// Reads the list after [delay], merging requests made meanwhile and
  /// never running two reads at once.
  Future<void> relistSoon(Duration delay) {
    final done = Completer<void>();
    _timer?.cancel();
    _timer = Timer(delay, () async {
      if (_reading != null) {
        _again = true;
        await _reading;
      } else {
        await _read();
      }
      if (!done.isCompleted) done.complete();
    });
    return done.future;
  }

  Future<void> _read() async {
    do {
      _again = false;
      if (_closed) return;
      final reading = _readOnce();
      _reading = reading;
      await reading;
      _reading = null;
    } while (_again && !_closed);
  }

  Future<void> _readOnce() async {
    try {
      final devices = await watch.list();
      if (_closed) return;
      everConnected = true;
      watch._emit([
        for (final device in devices)
          if (device.type == ConnectionType.usb) device,
      ]);
    } on Object {
      // A locked or untrusted phone: keep the previous list until a later
      // event reads it successfully.
    }
  }

  void close() {
    _closed = true;
    _timer?.cancel();
  }
}
