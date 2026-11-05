// studio: 027 — the text-level plist editor (AC-027-1…AC-027-4).
import 'package:studio_ext/src/shared/permissions/plist_text.dart';
import 'package:test/test.dart';

const _head =
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
    '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
    '<plist version="1.0">\n';

String _plist(String body, {String nl = '\n'}) =>
    '$_head<dict>\n$body</dict>\n</plist>\n'.replaceAll('\n', nl);

const _sample =
    '\t<!-- Keep this comment -->\n'
    '\t<key>CFBundleName</key>\n'
    '\t<string>\$(PRODUCT_NAME)</string>\n'
    '\t<key>UIBackgroundModes</key>\n'
    '\t<array>\n'
    '\t\t<string>remote-notification</string>\n'
    '\t</array>\n'
    '\t<key>NSAppTransportSecurity</key>\n'
    '\t<dict>\n'
    '\t\t<key>NSAllowsArbitraryLoads</key>\n'
    '\t\t<false/>\n'
    '\t\t<key>NSCameraUsageDescription</key>\n'
    '\t\t<string>nested, not the top level</string>\n'
    '\t</dict>\n'
    '\t<key>ITSAppUsesNonExemptEncryption</key>\n'
    '\t<false/>\n';

void main() {
  group('AC-027-1 reading', () {
    test('lists the top-level keys only', () {
      final text = PlistText(_plist(_sample));
      expect(text.keys, [
        'CFBundleName',
        'UIBackgroundModes',
        'NSAppTransportSecurity',
        'ITSAppUsesNonExemptEncryption',
      ]);
      expect(text.has('NSCameraUsageDescription'), isFalse);
      expect(text.indent, '\t');
    });

    test('a binary or non-dictionary plist is refused with a code', () {
      expect(
        () => PlistText('bplist00....'),
        throwsA(
          isA<PlistEditException>().having(
            (e) => e.code,
            'code',
            'permissions.binary_plist',
          ),
        ),
      );
      expect(
        () => PlistText('$_head<array/>\n</plist>\n'),
        throwsA(isA<PlistEditException>()),
      );
      expect(
        () => PlistText('$_head<dict>\n<key>A</key>\n'),
        throwsA(isA<PlistEditException>()),
      );
    });
  });

  group('AC-027-2 setting', () {
    test("a new key goes before the closing dict, in the file's style", () {
      final out = PlistText(_plist(_sample)).set(
        'NSCameraUsageDescription',
        'This app uses the camera to scan codes.',
      );
      expect(
        out,
        _plist(
          '$_sample'
          '\t<key>NSCameraUsageDescription</key>\n'
          '\t<string>This app uses the camera to scan codes.</string>\n',
        ),
      );
      // The comment and the variable survive, byte for byte.
      expect(out, contains('<!-- Keep this comment -->'));
      expect(out, contains(r'<string>$(PRODUCT_NAME)</string>'));
      expect(PlistText(out).has('NSCameraUsageDescription'), isTrue);
    });

    test('an existing key changes its value and nothing else', () {
      final before = _plist(_sample);
      final out = PlistText(before).set('ITSAppUsesNonExemptEncryption', true);
      expect(
        out,
        before.replaceFirst(
          '<key>ITSAppUsesNonExemptEncryption</key>\n\t<false/>',
          '<key>ITSAppUsesNonExemptEncryption</key>\n\t<true/>',
        ),
      );
    });

    test('values are escaped', () {
      final out = PlistText(
        _plist(_sample),
      ).set('NSCameraUsageDescription', 'Scan <codes> & "tickets"');
      expect(out, contains('Scan &lt;codes&gt; &amp; "tickets"'));
      expect(PlistText(out).has('NSCameraUsageDescription'), isTrue);
    });

    test('lists and dictionaries are written indented, and replaced whole', () {
      final out = PlistText(
        _plist(_sample),
      ).set('UIBackgroundModes', ['remote-notification', 'fetch']);
      expect(
        out,
        contains(
          '\t<key>UIBackgroundModes</key>\n'
          '\t<array>\n'
          '\t\t<string>remote-notification</string>\n'
          '\t\t<string>fetch</string>\n'
          '\t</array>\n',
        ),
      );
      final nested = PlistText(_plist('')).set('A', {
        'k': ['x'],
        'e': <String>[],
      });
      expect(
        nested,
        _plist(
          '\t<key>A</key>\n'
          '\t<dict>\n'
          '\t\t<key>k</key>\n'
          '\t\t<array>\n'
          '\t\t\t<string>x</string>\n'
          '\t\t</array>\n'
          '\t\t<key>e</key>\n'
          '\t\t<array/>\n'
          '\t</dict>\n',
        ),
      );
    });

    test('Windows line endings stay Windows line endings', () {
      final before = _plist(_sample, nl: '\r\n');
      final out = PlistText(before).set('NSCameraUsageDescription', 'Scan it.');
      expect(
        out.replaceAll('\r\n', '').contains('\n'),
        isFalse,
        reason: 'no bare LF was introduced',
      );
      expect(out, contains('<string>Scan it.</string>\r\n</dict>'));
    });

    test('into an entitlements file with nothing in it', () {
      final out = PlistText(
        '$_head<dict>\n</dict>\n</plist>\n',
      ).set('aps-environment', 'development');
      expect(
        out,
        '$_head<dict>\n'
        '\t<key>aps-environment</key>\n'
        '\t<string>development</string>\n'
        '</dict>\n</plist>\n',
      );
    });
  });

  group('AC-027-3 removing', () {
    test('takes the key and its value, and only those lines', () {
      final before = _plist(_sample);
      final out = PlistText(before).remove('UIBackgroundModes');
      expect(
        out,
        before.replaceFirst(
          '\t<key>UIBackgroundModes</key>\n'
              '\t<array>\n'
              '\t\t<string>remote-notification</string>\n'
              '\t</array>\n',
          '',
        ),
      );
    });

    test('a key that is not there leaves the text alone', () {
      final before = _plist(_sample);
      expect(PlistText(before).remove('NSMicrophoneUsageDescription'), before);
    });

    test('set then remove returns the original text', () {
      final before = _plist(_sample);
      final added = PlistText(before).set('NSCameraUsageDescription', 'x y z.');
      expect(PlistText(added).remove('NSCameraUsageDescription'), before);
    });
  });
}
