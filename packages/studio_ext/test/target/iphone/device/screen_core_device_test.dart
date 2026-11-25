import 'dart:convert';
import 'dart:io';

import 'package:studio_ext/target/iphone/device/screen_core_device.dart';
import 'package:test/test.dart';

void main() {
  test(
    'AC-048-E19 touch and buttons reach the iOS 27 viewer through the proxy: its Origin check passes',
    () async {
      // A stand-in for pymobiledevice3's server: POSTs from any other origin are 403.
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => upstream.close(force: true));
      final upstreamOrigin = 'http://127.0.0.1:${upstream.port}';
      upstream.listen((request) async {
        final origin = request.headers.value('origin');
        request.response.statusCode =
            request.method == 'POST' && origin != upstreamOrigin ? 403 : 204;
        await request.response.close();
      });
      final proxy = await PictureOnlyProxy.start(Uri.parse('$upstreamOrigin/'));
      addTearDown(proxy.close);
      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      final request = await client.postUrl(proxy.viewer.resolve('/tap'));
      // What a browser sends from the page it got from the proxy.
      request.headers.set('origin', 'http://127.0.0.1:${proxy.viewer.port}');
      request.headers.set('referer', '${proxy.viewer}');
      request.add(utf8.encode('{"x":0.5,"y":0.5}'));
      final response = await request.close();
      await response.drain<void>();
      expect(response.statusCode, 204, reason: 'the viewer accepted the tap');
    },
  );

  test(
    'AC-048-E20 the page sets the HEVC decoder size from the stream header (WebView2 would show a 1280x720 corner)',
    () {
      final out = PictureOnlyProxy.rewrite(
        '<html><head></head><body class="frame-on"></body></html>',
      );
      expect(out, contains('VideoDecoder.prototype.configure'));
      expect(out, contains('codedWidth:s.w,codedHeight:s.h'));
      expect(
        out.indexOf('VideoDecoder.prototype.configure'),
        lessThan(out.indexOf('</head>')),
        reason: 'before the viewer script runs',
      );
    },
  );

  test(
    'AC-048-E21 a drag reaches the phone in order, one event at a time, and always ends with the finger up',
    () async {
      final seen = <String>[];
      var busy = 0;
      var mostBusy = 0;
      final upstream = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => upstream.close(force: true));
      upstream.listen((request) async {
        busy++;
        if (busy > mostBusy) mostBusy = busy;
        seen.add(await utf8.decodeStream(request));
        await Future<void>.delayed(const Duration(milliseconds: 15));
        busy--;
        request.response.statusCode = 204;
        await request.response.close();
      });
      final proxy = await PictureOnlyProxy.start(
        Uri.parse('http://127.0.0.1:${upstream.port}/'),
      );
      addTearDown(proxy.close);
      final client = HttpClient();
      addTearDown(() => client.close(force: true));

      Future<int> post(String type, int x) async {
        final request = await client.postUrl(proxy.viewer.resolve('/touch'));
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode({'type': type, 'x': x, 'y': 100}));
        final response = await request.close();
        await response.drain<void>();
        return response.statusCode;
      }

      // Finger down, 40 quick moves, finger up. The page sends them one at a time,
      // so they arrive in order; the proxy answers at once and thins the moves.
      final answers = <int>[await post('contact', 0)];
      for (var x = 1; x <= 40; x++) {
        answers.add(await post('contact', x));
      }
      answers.add(await post('release', 40));
      expect(answers, everyElement(202));
      for (var i = 0; i < 100 && seen.length < 3; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));

      final events = [for (final s in seen) jsonDecode(s) as Map];
      expect(mostBusy, 1, reason: 'one request to the phone at a time');
      expect(events.first['x'], 0, reason: 'the gesture starts where it began');
      expect(events.last['type'], 'release', reason: 'the finger always lifts');
      expect(events.last['x'], 40);
      final contacts = [
        for (final e in events)
          if (e['type'] == 'contact') e['x'] as int,
      ];
      expect(
        contacts,
        orderedEquals([...contacts]..sort()),
        reason: 'in order',
      );
      expect(contacts.last, 40, reason: 'the newest position is kept');
      expect(
        events.length,
        lessThan(42),
        reason: 'a busy phone gets fewer moves',
      );
    },
  );

  test('AC-048-E22 the page sends touch events one at a time, in order', () {
    final out = PictureOnlyProxy.rewrite(
      '<html><head></head><body class="frame-on"></body></html>',
    );
    expect(out, contains("url!=='/touch'"));
    expect(out, contains('queue[n-1].contact'));
    expect(
      out.indexOf("url!=='/touch'"),
      lessThan(out.indexOf('</head>')),
      reason: 'before the viewer script runs',
    );
  });

  test('AC-048-E19 only Origin and Referer are rewritten', () {
    final upstream = Uri.parse('http://127.0.0.1:9000/');
    expect(
      PictureOnlyProxy.forwardedHeader(
        upstream,
        'origin',
        'http://127.0.0.1:1',
      ),
      'http://127.0.0.1:9000',
    );
    expect(
      PictureOnlyProxy.forwardedHeader(
        upstream,
        'referer',
        'http://127.0.0.1:1/x',
      ),
      'http://127.0.0.1:9000/',
    );
    expect(PictureOnlyProxy.forwardedHeader(upstream, 'cookie', 'a=b'), 'a=b');
  });

  test(
    'AC-048-E18 the iOS 27 viewer page shows the picture only (no bar, trays, bezel or buttons)',
    () {
      const page =
          '<html><head><title>x</title></head><body class="frame-on">'
          '<header id="topbar"></header><canvas id="c"></canvas></body></html>';
      final out = PictureOnlyProxy.rewrite(page);
      expect(out, contains('<body>'));
      expect(out, isNot(contains('frame-on">')));
      expect(out, contains('#topbar,#left-tray,#right-tray,#bottom-row,.hw'));
      expect(out, contains("localStorage.setItem('frameOn','false')"));
      expect(out.indexOf('<style>'), lessThan(out.indexOf('</head>')));
      expect(out.indexOf('setInterval(fit'), lessThan(out.indexOf('</body>')));
    },
  );
}
