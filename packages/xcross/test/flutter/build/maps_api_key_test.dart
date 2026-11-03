// studio: 016 — the Google Maps key for the generic runner
// (specs/016-push-firebase-maps, AC-016-8).
import 'dart:io';

import 'package:cli_kit/composition/native_host.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xcross/src/shared/flutter/build/maps_api_key.dart';
import 'package:xcross/src/shared/flutter/build/runner_shim.dart';

void main() {
  group('AC-016-8 the key AppDelegate passes', () {
    test('Swift literal', () {
      expect(
        MapsApiKeyLocator.fromSource(
          'GMSServices.provideAPIKey("abc-123")',
          objc: false,
        ),
        (literal: 'abc-123', plistKey: null),
      );
    });

    test('Objective-C literal', () {
      expect(
        MapsApiKeyLocator.fromSource(
          '[GMSServices provideAPIKey:@"abc-123"];',
          objc: true,
        ),
        (literal: 'abc-123', plistKey: null),
      );
    });

    test('Swift Info.plist lookup, inline and through a constant', () {
      expect(
        MapsApiKeyLocator.fromSource(
          'GMSServices.provideAPIKey(Bundle.main.object('
          'forInfoDictionaryKey: "GMSApiKey") as! String)',
          objc: false,
        ),
        (literal: null, plistKey: 'GMSApiKey'),
      );
      expect(
        MapsApiKeyLocator.fromSource(
          'let key = Bundle.main.object(forInfoDictionaryKey: "MapsKey") '
          'as? String ?? ""\nGMSServices.provideAPIKey(key)',
          objc: false,
        ),
        (literal: null, plistKey: 'MapsKey'),
      );
    });

    test('Objective-C Info.plist lookup through a variable', () {
      expect(
        MapsApiKeyLocator.fromSource(
          'NSString *key = [[NSBundle mainBundle] '
          'objectForInfoDictionaryKey:@"MapsKey"];\n'
          '[GMSServices provideAPIKey:key];',
          objc: true,
        ),
        (literal: null, plistKey: 'MapsKey'),
      );
    });

    test('an argument xcross cannot follow', () {
      expect(
        MapsApiKeyLocator.fromSource(
          'GMSServices.provideAPIKey(Secrets.mapsKey())',
          objc: false,
        ),
        (literal: null, plistKey: null),
      );
    });

    test('commented-out calls are ignored; URLs in strings are kept', () {
      final code = MapsApiKeyLocator.stripComments(
        '// GMSServices.provideAPIKey("old")\n'
        '/* GMSServices.provideAPIKey("older") */\n'
        'let url = "https://example.com"\n',
      );
      expect(code, contains('"https://example.com"'));
      expect(MapsApiKeyLocator.fromSource(code, objc: false), isNull);
    });
  });

  group('AC-016-8 locate in a project', () {
    late Directory root;
    setUp(() {
      root = Directory.systemTemp.createTempSync('maps-key-');
      Directory(p.join(root.path, 'ios', 'Runner')).createSync(recursive: true);
    });
    tearDown(() => root.deleteSync(recursive: true));

    void write(String name, String text) =>
        File(p.join(root.path, 'ios', 'Runner', name)).writeAsStringSync(text);

    MapsApiKey? locate([Map<String, String> settings = const {}]) =>
        MapsApiKeyLocator(
          fileSystem: detectPlatformHost().fileSystem,
          paths: p.context,
          resolveVariable: (name) => settings[name],
        ).locate(root.path);

    test('no call, nothing to pass', () {
      write('AppDelegate.swift', 'import Flutter');
      expect(locate(), isNull);
    });

    test('a literal names its file as the source', () {
      write(
        'AppDelegate.swift',
        'import GoogleMaps\nGMSServices.provideAPIKey("k-1")',
      );
      final found = locate()!;
      expect(found.key, 'k-1');
      expect(found.source, 'AppDelegate.swift');
    });

    test(r'an Info.plist value with $(VAR) is resolved from xcconfig', () {
      write(
        'AppDelegate.swift',
        'GMSServices.provideAPIKey(Bundle.main.object('
            'forInfoDictionaryKey: "GMSApiKey") as! String)',
      );
      write(
        'Info.plist',
        [
          '<?xml version="1.0" encoding="UTF-8"?>',
          '<plist version="1.0"><dict>',
          r'<key>GMSApiKey</key><string>$(MAPS_API_KEY)</string>',
          '</dict></plist>',
        ].join('\n'),
      );
      final found = locate({'MAPS_API_KEY': 'k-from-xcconfig'})!;
      expect(found.key, 'k-from-xcconfig');
      expect(found.source, 'AppDelegate.swift → Info.plist GMSApiKey');
      expect(locate()!.resolved, isFalse);
    });
  });

  group('AC-016-8 the generic runner source', () {
    test('without a key it is unchanged', () {
      final source = RunnerShim.runnerObjcSource(
        hasPlugins: true,
        verbose: false,
      );
      expect(source, isNot(contains('GMSServices')));
      expect(source, isNot(contains('XcrossProvideMapsKey')));
    });

    test('with a key it calls provideAPIKey before super', () {
      final source = RunnerShim.runnerObjcSource(
        hasPlugins: true,
        verbose: false,
        mapsApiKey: 'k"1',
      );
      expect(source, contains('NSClassFromString(@"GMSServices")'));
      expect(source, contains(r'@"k\"1"'));
      final call = source.indexOf('XcrossProvideMapsKey();');
      final superCall = source.indexOf('[super application:application');
      expect(call, greaterThan(0));
      expect(call, lessThan(superCall));
    });
  });
}
