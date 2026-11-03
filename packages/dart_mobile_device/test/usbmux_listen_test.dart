// studio: 017 — usbmuxd Listen client (specs/017-device-watcher).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_mobile_device/host/shared/usbmux_listen.dart';
import 'package:meta/meta.dart';
import 'package:propertylistserialization/propertylistserialization.dart';
import 'package:test/test.dart';

@internal
Map<String, Object> attached(int id, String udid, [String type = 'USB']) => {
  'MessageType': 'Attached',
  'DeviceID': id,
  'Properties': {'ConnectionType': type, 'DeviceID': id, 'SerialNumber': udid},
};

void main() {
  group('AC-017-1 frames', () {
    test('header carries length, version 1, message 8 and the tag', () {
      final frame = UsbmuxFrames.encode(const {
        'MessageType': 'Listen',
      }, tag: 7);
      final header = ByteData.sublistView(frame);
      expect(header.getUint32(0, Endian.little), frame.length);
      expect(header.getUint32(4, Endian.little), 1);
      expect(header.getUint32(8, Endian.little), 8);
      expect(header.getUint32(12, Endian.little), 7);
      final body = utf8.decode(frame.sublist(16));
      expect(PropertyListSerialization.propertyListWithString(body), {
        'MessageType': 'Listen',
      });
    });

    test('decoder joins split frames and splits joined ones', () {
      final a = UsbmuxFrames.encode(attached(1, 'A'));
      final b = UsbmuxFrames.encode(const {
        'MessageType': 'Detached',
        'DeviceID': 1,
      });
      final decoder = UsbmuxFrameDecoder();
      expect(decoder.add(a.sublist(0, 10)), isEmpty);
      final all = [...a.sublist(10), ...b];
      final messages = decoder.add(all);
      expect(messages.map((m) => m['MessageType']), ['Attached', 'Detached']);
    });
  });

  group('AC-017-1 Listen session', () {
    late ServerSocket server;
    late StreamController<Socket> clients;

    setUp(() async {
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      clients = StreamController<Socket>();
      server.listen(clients.add);
    });
    tearDown(() async {
      await server.close();
      await clients.close();
    });

    String address() => '127.0.0.1:${server.port}';

    test('sends Listen and reports attaches and detaches', () async {
      final events = <UsbmuxEvent>[];
      final listener = UsbmuxListener(address: address());
      final subscription = listener.listen().listen(events.add);
      final client = await clients.stream.first;
      final request = await client.first;
      final decoded = UsbmuxFrameDecoder().add(request).single;
      expect(decoded['MessageType'], 'Listen');

      client
        ..add(UsbmuxFrames.encode(const {'MessageType': 'Result', 'Number': 0}))
        ..add(UsbmuxFrames.encode(attached(3, '00008030-AAA')))
        ..add(UsbmuxFrames.encode(attached(4, 'BBB', 'Network')))
        ..add(
          UsbmuxFrames.encode(const {'MessageType': 'Detached', 'DeviceID': 3}),
        );
      await client.flush();
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(events, hasLength(3));
      final first = events[0] as UsbmuxAttached;
      expect(first.deviceId, 3);
      expect(first.udid, '00008030-AAA');
      expect(first.isUsb, isTrue);
      expect((events[1] as UsbmuxAttached).isUsb, isFalse);
      expect(events[2], isA<UsbmuxDetached>());
      await subscription.cancel();
      client.destroy();
    });

    test(
      'a closed connection ends the stream with UsbmuxUnavailable',
      () async {
        final done = Completer<Object>();
        UsbmuxListener(
          address: address(),
        ).listen().listen((_) {}, onError: done.complete);
        final client = await clients.stream.first;
        await client.first;
        client.destroy();
        expect(await done.future, isA<UsbmuxUnavailable>());
      },
    );

    test('a refused Listen is an error', () async {
      final done = Completer<Object>();
      UsbmuxListener(
        address: address(),
      ).listen().listen((_) {}, onError: done.complete);
      final client = await clients.stream.first;
      await client.first;
      client.add(
        UsbmuxFrames.encode(const {'MessageType': 'Result', 'Number': 3}),
      );
      final error = await done.future;
      expect(error, isA<UsbmuxUnavailable>());
      expect('$error', contains('code 3'));
      client.destroy();
    });
  });

  test('AC-017-1 an unreachable service is an error, not a hang', () async {
    final unused = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = unused.port;
    await unused.close();
    final error = await UsbmuxListener(
      address: '127.0.0.1:$port',
    ).listen().first.then<Object>((e) => e, onError: (Object e) => e);
    expect(error, isA<UsbmuxUnavailable>());
  });
}
