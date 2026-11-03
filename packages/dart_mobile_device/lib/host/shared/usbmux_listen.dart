// studio: 017 — usbmuxd `Listen`: attach/detach events without a
// pymobiledevice3 process per event (specs/017-device-watcher).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:propertylistserialization/propertylistserialization.dart';

/// One change reported by usbmuxd.
sealed class UsbmuxEvent {
  const UsbmuxEvent(this.deviceId);

  /// usbmuxd's id for the connection (not the UDID).
  final int deviceId;
}

/// A device was connected, or was already connected when listening began.
final class UsbmuxAttached extends UsbmuxEvent {
  const UsbmuxAttached(
    super.deviceId, {
    required this.udid,
    required this.connectionType,
  });

  /// `SerialNumber`: the device's UDID.
  final String udid;

  /// `USB` or `Network`.
  final String connectionType;

  bool get isUsb => connectionType.toUpperCase() == 'USB';
}

/// A device went away.
final class UsbmuxDetached extends UsbmuxEvent {
  const UsbmuxDetached(super.deviceId);
}

/// The device service could not be reached, refused `Listen`, or dropped
/// the connection.
final class UsbmuxUnavailable implements Exception {
  const UsbmuxUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

/// usbmuxd's plist wire format: a 16-byte little-endian header (`length`
/// including the header, `version` 1, `message` 8, `tag`) and an XML plist.
abstract final class UsbmuxFrames {
  static const headerLength = 16;
  static const plistVersion = 1;
  static const plistMessage = 8;

  /// [message] as one frame.
  static Uint8List encode(Map<String, Object> message, {int tag = 1}) {
    final body = utf8.encode(
      PropertyListSerialization.stringWithPropertyList(message),
    );
    final frame = ByteData(headerLength + body.length)
      ..setUint32(0, headerLength + body.length, Endian.little)
      ..setUint32(4, plistVersion, Endian.little)
      ..setUint32(8, plistMessage, Endian.little)
      ..setUint32(12, tag, Endian.little);
    final bytes = frame.buffer.asUint8List()
      ..setRange(headerLength, headerLength + body.length, body);
    return bytes;
  }
}

/// Splits a byte stream into usbmuxd plist messages.
final class UsbmuxFrameDecoder {
  final _buffer = BytesBuilder(copy: false);
  Uint8List _pending = Uint8List(0);

  /// The complete messages [chunk] finishes, in order.
  List<Map<String, Object?>> add(List<int> chunk) {
    _buffer
      ..add(_pending)
      ..add(chunk);
    var bytes = _buffer.takeBytes();
    final messages = <Map<String, Object?>>[];
    while (bytes.length >= UsbmuxFrames.headerLength) {
      final length = ByteData.sublistView(bytes).getUint32(0, Endian.little);
      if (length < UsbmuxFrames.headerLength) {
        throw const UsbmuxUnavailable('The device service sent a bad frame.');
      }
      if (bytes.length < length) break;
      final body = utf8.decode(
        bytes.sublist(UsbmuxFrames.headerLength, length),
        allowMalformed: true,
      );
      final Object? plist;
      try {
        plist = PropertyListSerialization.propertyListWithString(body);
      } on Object {
        throw const UsbmuxUnavailable(
          'The device service sent a message that is not a property list.',
        );
      }
      if (plist is Map) {
        messages.add({for (final e in plist.entries) '${e.key}': e.value});
      }
      bytes = bytes.sublist(length);
    }
    _pending = bytes;
    return messages;
  }
}

/// Connects to usbmuxd at an address in `USBMUXD_SOCKET_ADDRESS` form
/// (`host:port` or a unix socket path, optionally `unix:`-prefixed).
typedef UsbmuxConnect = Future<Socket> Function(String address);

/// A usbmuxd `Listen` session.
final class UsbmuxListener {
  UsbmuxListener({required this.address, UsbmuxConnect? connect})
    : _connect = connect ?? connectUsbmux;

  final String address;
  final UsbmuxConnect _connect;

  static final _hostPort = RegExp(r'^\[?([^\[\]/]+?)\]?:(\d+)$');

  /// The default [UsbmuxConnect].
  static Future<Socket> connectUsbmux(String address) {
    final trimmed = address.trim();
    final tcp = _hostPort.firstMatch(trimmed);
    if (tcp != null) {
      return Socket.connect(
        tcp[1],
        int.parse(tcp[2]!),
        timeout: const Duration(seconds: 2),
      );
    }
    final path = trimmed.startsWith('unix:') ? trimmed.substring(5) : trimmed;
    return Socket.connect(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
      timeout: const Duration(seconds: 2),
    );
  }

  /// The `Listen` request.
  @visibleForTesting
  static const listenRequest = <String, Object>{
    'MessageType': 'Listen',
    'ClientVersionString': 'xcross',
    'ProgName': 'xcross',
    'kLibUSBMuxVersion': 3,
  };

  /// Attach and detach events until the subscription is cancelled. Devices
  /// already connected arrive first as attaches. The stream ends with a
  /// [UsbmuxUnavailable] error when the service cannot be reached, refuses,
  /// or closes the connection.
  Stream<UsbmuxEvent> listen() {
    Socket? socket;
    StreamSubscription<List<int>>? subscription;
    late final StreamController<UsbmuxEvent> controller;
    void fail(String message) {
      if (controller.isClosed) return;
      controller.addError(UsbmuxUnavailable(message));
      unawaited(controller.close());
    }

    controller = StreamController<UsbmuxEvent>(
      onListen: () async {
        try {
          socket = await _connect(address);
        } on Object catch (error) {
          fail('The device service is not reachable at $address ($error).');
          return;
        }
        final decoder = UsbmuxFrameDecoder();
        subscription = socket!.listen(
          (chunk) {
            final List<Map<String, Object?>> messages;
            try {
              messages = decoder.add(chunk);
            } on UsbmuxUnavailable catch (error) {
              fail(error.message);
              socket?.destroy();
              return;
            }
            for (final message in messages) {
              final event = _event(message);
              if (event case final UsbmuxUnavailable refused) {
                fail(refused.message);
                socket?.destroy();
                return;
              }
              if (event is UsbmuxEvent && !controller.isClosed) {
                controller.add(event);
              }
            }
          },
          onError: (Object error) =>
              fail('The device service connection failed ($error).'),
          onDone: () => fail('The device service closed the connection.'),
          cancelOnError: true,
        );
        socket!.add(UsbmuxFrames.encode(listenRequest));
      },
      onCancel: () async {
        await subscription?.cancel();
        socket?.destroy();
      },
    );
    return controller.stream;
  }

  /// The event for [message], a [UsbmuxUnavailable] for a refused `Listen`,
  /// or `null` for messages that change nothing (`Result` 0, `Paired`).
  static Object? _event(Map<String, Object?> message) {
    final id = message['DeviceID'];
    switch (message['MessageType']) {
      case 'Result':
        final number = message['Number'];
        return number == 0 || number == null
            ? null
            : UsbmuxUnavailable(
                'The device service refused to report devices (code $number).',
              );
      case 'Attached':
        final properties = message['Properties'];
        if (id is! int || properties is! Map) return null;
        final udid = properties['SerialNumber'];
        if (udid is! String || udid.isEmpty) return null;
        return UsbmuxAttached(
          id,
          udid: udid,
          connectionType: '${properties['ConnectionType'] ?? 'USB'}',
        );
      case 'Detached':
        return id is int ? UsbmuxDetached(id) : null;
    }
    return null;
  }
}
