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

  /// Runs before the viewer's own script. WebView2's HEVC decoder starts at a
  /// default 1280x720 when `VideoDecoder.configure` has no `codedWidth` and
  /// `codedHeight`, and shows only that corner of the phone's picture (a
  /// browser such as Brave sizes it from the stream itself). The real size is
  /// in the stream's own header: this reads it from the SPS in the `hvcC`
  /// description and passes it on. Without a readable SPS nothing changes.
  static const _decoderSize = r'''
<script>
(function(){
  if(typeof VideoDecoder==='undefined') return;
  function rbsp(b){var o=[];for(var i=0;i<b.length;i++){if(i>=2&&b[i]===3&&b[i-1]===0&&b[i-2]===0)continue;o.push(b[i]);}return Uint8Array.from(o);}
  function parse(r){
    var bit=0;
    function u(n){var v=0;for(var i=0;i<n;i++){v=v*2+((r[bit>>3]>>(7-(bit&7)))&1);bit++;}return v;}
    function ue(){var z=0;while(u(1)===0&&z<32)z++;return z===0?0:Math.pow(2,z)-1+u(z);}
    u(4);var sub=u(3);u(1);u(8);u(32);u(48);u(8);
    var sp=[],sl=[],i;
    for(i=0;i<sub;i++){sp.push(u(1));sl.push(u(1));}
    if(sub>0)for(i=sub;i<8;i++)u(2);
    for(i=0;i<sub;i++){if(sp[i])u(88);if(sl[i])u(8);}
    ue();var chroma=ue();if(chroma===3)u(1);
    return {w:ue(),h:ue()};
  }
  function size(d){
    var b=new Uint8Array(d.buffer?d.buffer.slice(d.byteOffset,d.byteOffset+d.byteLength):d);
    var p=22,arrays=b[p++];
    for(var a=0;a<arrays;a++){
      var type=b[p++]&63,num=(b[p]<<8)|b[p+1];p+=2;
      for(var n=0;n<num;n++){
        var len=(b[p]<<8)|b[p+1];p+=2;
        if(type===33)return parse(rbsp(b.subarray(p+2,p+len)));
        p+=len;
      }
    }
    return null;
  }
  var configure=VideoDecoder.prototype.configure;
  VideoDecoder.prototype.configure=function(c){
    try{
      var s=c&&c.description?size(c.description):null;
      if(s&&s.w>0&&s.h>0&&!c.codedWidth)c=Object.assign({},c,{codedWidth:s.w,codedHeight:s.h});
    }catch(e){}
    return configure.call(this,c);
  };
})();
</script>''';

  /// Runs before the viewer's own script. The viewer posts every pointer event
  /// with its own `fetch`, all at once: they travel on several connections and
  /// can arrive out of order, so a "finger up" may land before the last "finger
  /// moved" and leave the finger down on the phone (a page swipe stops halfway
  /// and stays there). This sends them one at a time, in order, and thins out
  /// a run of "moved" events while one is on its way (the first and the newest
  /// stay; "down" and "up" are never dropped).
  static const _touchOrder = r'''
<script>
(function(){
  var orig=window.fetch.bind(window),queue=[],running=false;
  function pump(){
    if(running)return;running=true;
    (function next(){
      var e=queue.shift();
      if(!e){running=false;return;}
      orig(e.url,e.opts).then(e.done,function(){e.done(new Response(null,{status:502}));}).then(next,next);
    })();
  }
  window.fetch=function(url,opts){
    if(url!=='/touch'||!opts||opts.method!=='POST')return orig(url,opts);
    return new Promise(function(resolve){
      var contact=false;
      try{contact=JSON.parse(opts.body).type==='contact';}catch(e){}
      var item={url:url,opts:opts,done:resolve,contact:contact},n=queue.length;
      if(contact&&n>=2&&queue[n-1].contact&&queue[n-2].contact){
        queue[n-1].done(new Response(null,{status:202}));
        queue[n-1]=item;
      }else queue.push(item);
      pump();
    });
  };
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
      .replaceFirst('</head>', '$_head$_decoderSize$_touchOrder</head>')
      .replaceFirst('</body>', '$_tail</body>');

  late final _TouchRelay _touch = _TouchRelay(_sendTouch);

  Future<void> _sendTouch(String body) async {
    final out = await _client.openUrl('POST', _upstream.resolve('/touch'));
    out.headers
      ..contentType = ContentType.json
      ..set('origin', _upstream.origin);
    out.write(body);
    final response = await out.close();
    await response.drain<void>();
  }

  /// The viewer posts every pointer event as its own, unordered request. Over
  /// several connections the "finger up" can overtake a "finger moved", and
  /// the phone is left with the finger down halfway between two pages. So
  /// touch events are answered at once and handed to the phone one at a time,
  /// in the order they arrived (see [_TouchRelay]).
  Future<void> _handleTouch(HttpRequest request) async {
    try {
      final body = await utf8.decodeStream(request);
      final Object? json = jsonDecode(body);
      final contact = json is Map && json['type'] == 'contact';
      _touch.add(body, contact: contact);
      request.response.statusCode = HttpStatus.accepted;
    } on Object {
      request.response.statusCode = HttpStatus.badRequest;
    }
    await request.response.close();
  }

  Future<void> _handle(HttpRequest request) async {
    if (request.method == 'POST' && request.uri.path == '/touch') {
      return _handleTouch(request);
    }
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

/// Hands touch events to the phone one at a time, in order, without ever
/// dropping a "finger up". While the phone is busy, a run of "finger moved"
/// events is thinned out: the first of the gesture and the newest are kept.
final class _TouchRelay {
  _TouchRelay(this._send);

  final Future<void> Function(String body) _send;
  final _queue = <({String body, bool contact})>[];
  bool _running = false;

  void add(String body, {required bool contact}) {
    final n = _queue.length;
    if (contact && n >= 2 && _queue[n - 1].contact && _queue[n - 2].contact) {
      _queue[n - 1] = (body: body, contact: true);
    } else {
      _queue.add((body: body, contact: contact));
    }
    unawaited(_pump());
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty) {
        final next = _queue.removeAt(0);
        try {
          await _send(next.body);
        } on Object {
          // The viewer's next event goes on.
        }
      }
    } finally {
      _running = false;
    }
  }
}
