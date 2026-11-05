// studio: 027 — the permission switches permission_handler_apple needs from the
// project's Info.plist and Podfile (AC-027-20).
import 'package:studio_ext/shared/plugins/permission_macros.dart';
import 'package:test/test.dart';

String _plist(List<String> keys) {
  final entries = keys.map((k) => '<key>$k</key><string>Why.</string>').join();
  return '<plist version="1.0"><dict>\n'
      '<key>CFBundleName</key><string>x</string>\n'
      '$entries\n'
      '</dict></plist>';
}

void main() {
  test('a purpose string in Info.plist turns its permission on', () {
    final environment = PermissionMacros.environment(
      infoPlist: _plist([
        'NSCameraUsageDescription',
        'NSPhotoLibraryUsageDescription',
        'NSLocationWhenInUseUsageDescription',
      ]),
    );
    expect(environment, {
      'PERMISSION_CAMERA': '1',
      'PERMISSION_LOCATION': '1',
      'PERMISSION_LOCATION_WHENINUSE': '1',
      'PERMISSION_PHOTOS': '1',
    });
  });

  test('add-only photos turns on both photo macros, like the plugin does', () {
    final environment = PermissionMacros.environment(
      infoPlist: _plist(['NSPhotoLibraryAddUsageDescription']),
    );
    expect(environment, {
      'PERMISSION_PHOTOS': '1',
      'PERMISSION_PHOTOS_ADD_ONLY': '1',
    });
  });

  test(
    'the Podfile decides: =1 turns on, =0 turns off even with the string',
    () {
      final environment = PermissionMacros.environment(
        infoPlist: _plist([
          'NSCameraUsageDescription',
          'NSMicrophoneUsageDescription',
        ]),
        podfile: '''
        config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
          'inherited',
          'PERMISSION_CAMERA=0',
          "PERMISSION_CONTACTS=1",
        ]
      ''',
      );
      expect(environment, {
        'PERMISSION_CAMERA': '0',
        'PERMISSION_CONTACTS': '1',
        'PERMISSION_MICROPHONE': '1',
      });
    },
  );

  test('nothing declared, nothing on; unrelated keys are ignored', () {
    expect(PermissionMacros.environment(), isEmpty);
    expect(
      PermissionMacros.environment(
        infoPlist: _plist(['UIBackgroundModes', 'NSAppTransportSecurity']),
        podfile: "platform :ios, '15.0'",
      ),
      isEmpty,
    );
  });

  test('every macro the table names is a PERMISSION_ switch', () {
    for (final macros in PermissionMacros.byInfoPlistKey.values) {
      for (final macro in macros) {
        expect(macro, startsWith('PERMISSION_'));
      }
    }
  });
}
