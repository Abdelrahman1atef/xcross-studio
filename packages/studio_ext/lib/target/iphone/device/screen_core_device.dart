// studio: 048 — the live iPhone screen through Apple's own screen service
// (CoreDevice display service, iOS 27+): HEVC video and live touch, no driver
// change. pymobiledevice3 serves a viewer page on 127.0.0.1.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:studio_ext/target/iphone/device/screen_touch.dart';

/// Why Apple's screen service could not start.
final class CoreDeviceScreenUnavailable implements Exception {
  const CoreDeviceScreenUnavailable(this.message);
  final String message;

  @override
  String toString() => message;
}

/// A running Apple screen service viewer.
abstract interface class CoreDeviceScreenSession {
  /// `http://127.0.0.1:<port>/`: the viewer page (picture and touch).
  Uri get viewer;

  /// The tool's output lines (for errors).
  Stream<String> get output;

  Future<int> get exitCode;

  Future<void> stop();
}

/// Starts Apple's screen service for an iPhone that has it.
abstract interface class CoreDeviceScreen {
  /// The iPhone's iOS major version (0 when unknown).
  Future<int> iosMajor(String udid);

  /// Starts the viewer; throws [CoreDeviceScreenUnavailable] with a short reason on failure.
  Future<CoreDeviceScreenSession> start(String udid);
}

/// [CoreDeviceScreen] through the engine's pymobiledevice3.
final class PymdCoreDeviceScreen implements CoreDeviceScreen {
  PymdCoreDeviceScreen(
    this._tools, {
    this.readyTimeout = const Duration(seconds: 60),
    Future<bool> Function(Uri)? answers,
  }) : _answers = answers ?? _httpAnswers;

  /// The first iOS with the display service.
  static const firstIos = 27;

  final ScreenTouchTools _tools;
  final Duration readyTimeout;
  final Future<bool> Function(Uri) _answers;

  @override
  Future<int> iosMajor(String udid) async {
    try {
      final Object? info = jsonDecode(
        await _tools.run([
          'lockdown',
          'info',
          '--udid',
          udid,
        ], timeout: const Duration(seconds: 30)),
      );
      if (info case {'ProductVersion': final String version}) {
        return int.tryParse(version.split('.').first) ?? 0;
      }
    } on Object {
      // Unknown.
    }
    return 0;
  }

  @override
  Future<CoreDeviceScreenSession> start(String udid) async {
    // The service is on the developer image; "already mounted" is fine.
    try {
      await _tools.run([
        'mounter',
        'auto-mount',
        '--udid',
        udid,
      ], timeout: const Duration(minutes: 3));
    } on Object {
      // A real failure shows up as the service missing below.
    }
    final port = await _tools.freePort();
    final process = await _tools.start([
      'developer',
      'core-device',
      'display',
      'serve-web',
      '--userspace',
      '--no-audio',
      '--http-port',
      '$port',
    ]);
    final viewer = Uri.parse('http://127.0.0.1:$port/');
    final lines = <String>[];
    final output = process.output.asBroadcastStream();
    final sub = output.listen((line) {
      lines.add(line);
      if (lines.length > 40) lines.removeAt(0);
    });
    var exited = false;
    unawaited(process.exitCode.then((_) => exited = true));
    final deadline = DateTime.now().add(readyTimeout);
    var ready = false;
    while (!exited && DateTime.now().isBefore(deadline)) {
      if (await _answers(viewer)) {
        ready = true;
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (ready) {
      // The page answers before the video starts: a missing service shows up
      // in the log right after.
      await Future<void>.delayed(const Duration(seconds: 2));
      if (lines.any((l) => l.contains('does not offer'))) ready = false;
    }
    await sub.cancel();
    if (!ready || exited) {
      await process.kill();
      throw CoreDeviceScreenUnavailable(_reason(lines));
    }
    final proxy = await PictureOnlyProxy.start(viewer);
    return _Session(proxy.viewer, process, output, proxy);
  }

  static String _reason(List<String> lines) {
    if (lines.any((l) => l.contains('does not offer'))) {
      return "This iPhone does not offer Apple's screen service (iOS 27 or "
          'later with Developer Mode on is needed).';
    }
    final last = lines.lastWhere(
      (l) => l.contains('Error') || l.contains('error'),
      orElse: () => '',
    );
    return last.isEmpty
        ? "Apple's screen service did not start."
        : "Apple's screen service did not start: ${last.trim()}";
  }

  static Future<bool> _httpAnswers(Uri uri) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
    try {
      final response = await (await client.getUrl(uri)).close();
      await response.drain<void>();
      return response.statusCode == 200;
    } on Object {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}

final class _Session implements CoreDeviceScreenSession {
  _Session(this.viewer, this._process, this.output, this._proxy);

  @override
  final Uri viewer;
  final TouchProcess _process;
  final PictureOnlyProxy _proxy;

  @override
  final Stream<String> output;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  Future<void> stop() async {
    await _proxy.close();
    await _process.kill();
  }
}

/// Serves pymobiledevice3's viewer as the phone picture only: Studio draws
/// its own frame and buttons, so the page's bar, side panels, bezel and
/// buttons are hidden and the picture fills the window. Everything else
/// (video, touch, buttons) passes through to the real viewer unchanged.
final class PictureOnlyProxy {
  PictureOnlyProxy._(this._server, this._upstream, this._client);

  final HttpServer _server;
  final Uri _upstream;
  final HttpClient _client;

  Uri get viewer => Uri.parse('http://127.0.0.1:${_server.port}/');

  static Future<PictureOnlyProxy> start(Uri upstream) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final proxy = PictureOnlyProxy._(server, upstream, HttpClient());
    server.listen((request) => unawaited(proxy._handle(request)));
    return proxy;
  }

  static const _head = '''
<script>try{localStorage.setItem('frameOn','false');localStorage.setItem('zoom','1');}catch(e){}</script>
<style>
#topbar,#left-tray,#right-tray,#bottom-row,.hw,#hw-tooltip,#help-overlay,#stage::before{display:none!important}
html,body{margin:0!important;padding:0!important;background:#000!important;overflow:hidden!important;width:100%;height:100%}
#workspace,#stage-wrap,#stage{margin:0!important;padding:0!important;gap:0!important;width:100vw!important;height:100vh!important;max-width:none!important;display:flex!important;align-items:center!important;justify-content:center!important}
#device-frame{border:0!important;padding:0!important;background:none!important;box-shadow:none!important;border-radius:0!important}
#c{border-radius:0!important}
</style>''';

  static const _tail = '''
<script>
(function(){
  function fit(){
    var c=document.getElementById('c'); if(!c||!c.width||!c.height) return;
    var s=Math.min(window.innerWidth/c.width, window.innerHeight/c.height);
    var w=(c.width*s)+'px', h=(c.height*s)+'px';
    if(c.style.width!==w) c.style.width=w;
    if(c.style.height!==h) c.style.height=h;
  }
  document.body.classList.remove('frame-on');
  window.addEventListener('resize', fit);
  setInterval(fit, 300);
})();
</script>''';

  /// The value of request header [name] as the real viewer should see it.
  /// pymobiledevice3's server answers every POST (touch, buttons, restart,
  /// keyframe request) with 403 when `Origin` is not its own address, and the
  /// page reached through this proxy has the proxy's address: so `Origin` and
  /// `Referer` are rewritten to the viewer's own. Everything else is kept.
  static String forwardedHeader(Uri upstream, String name, String value) =>
      switch (name) {
        'origin' => upstream.origin,
        'referer' => '${upstream.origin}/',
        _ => value,
      };

  /// The viewer page with [_head] and [_tail] added.
  static String rewrite(String html) => html
      .replaceFirst('<body class="frame-on">', '<body>')
      .replaceFirst('</head>', '$_head</head>')
      .replaceFirst('</body>', '$_tail</body>');

  Future<void> _handle(HttpRequest request) async {
    try {
      final target = _upstream.resolve(request.uri.toString());
      final out = await _client.openUrl(request.method, target);
      out.followRedirects = false;
      request.headers.forEach((name, values) {
        if (name == 'host' || name == 'content-length') return;
        for (final v in values) {
          out.headers.add(name, forwardedHeader(_upstream, name, v));
        }
      });
      if (request.contentLength > 0) out.contentLength = request.contentLength;
      await out.addStream(request);
      final response = await out.close();
      final page =
          request.method == 'GET' &&
          (request.uri.path == '/' || request.uri.path == '/index.html');
      request.response.statusCode = response.statusCode;
      response.headers.forEach((name, values) {
        if (name == 'content-length' || name == 'transfer-encoding') return;
        for (final v in values) {
          request.response.headers.add(name, v);
        }
      });
      if (page) {
        final html = await utf8.decodeStream(response);
        request.response.write(rewrite(html));
      } else {
        request.response.bufferOutput = false;
        await request.response.addStream(response);
      }
      await request.response.close();
    } on Object {
      try {
        request.response.statusCode = HttpStatus.badGateway;
        await request.response.close();
      } on Object {
        // The viewer went away.
      }
    }
  }

  Future<void> close() async {
    await _server.close(force: true);
    _client.close(force: true);
  }
}
