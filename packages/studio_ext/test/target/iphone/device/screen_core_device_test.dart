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
