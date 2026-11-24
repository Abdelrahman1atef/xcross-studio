import 'package:studio_ext/target/iphone/device/screen_core_device.dart';
import 'package:test/test.dart';

void main() {
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
