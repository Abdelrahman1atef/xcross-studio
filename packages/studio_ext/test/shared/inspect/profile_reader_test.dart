import 'dart:convert';
import 'dart:typed_data';

import 'package:studio_ext/src/shared/inspect/inspect_report.dart';
import 'package:studio_ext/src/shared/inspect/profile_reader.dart';
import 'package:studio_ext/src/shared/inspect/report_json.dart';
import 'package:test/test.dart';

import '../../support/fixture_builder.dart';

void main() {
  const cases = {
    ProfileKind.development: (getTaskAllow: true, devices: true, all: false),
    ProfileKind.adHoc: (getTaskAllow: false, devices: true, all: false),
    ProfileKind.appStore: (getTaskAllow: false, devices: false, all: false),
    ProfileKind.enterprise: (getTaskAllow: false, devices: false, all: true),
  };

  for (final indefinite in [false, true]) {
    final encoding = indefinite ? 'BER indefinite' : 'DER';
    for (final MapEntry(key: kind, value: shape) in cases.entries) {
      test('AC-001-3 ${kind.wire} profile ($encoding)', () {
        final summary = readProfile(
          mobileProvision(
            profilePlist(
              bundleId: 'com.example.app',
              getTaskAllow: shape.getTaskAllow,
              devices: shape.devices,
              allDevices: shape.all,
            ),
            indefinite: indefinite,
          ),
        );
        expect(summary, isNotNull);
        expect(summary!.kind, kind);
        expect(summary.teamId, 'TEAMID1234');
        expect(summary.uuid, '11111111-2222-3333-4444-555555555555');
        expect(summary.creationDate, '2026-01-01T00:00:00Z');
        expect(summary.expirationDate, '2027-01-01T00:00:00Z');
        expect(summary.platforms, ['iOS']);
        expect(summary.provisionsAllDevices, shape.all);
        expect(summary.deviceCount, shape.devices ? plantedUdids.length : null);
        expect(summary.certificateCount, 1);
        expect(
          summary.entitlements['application-identifier'],
          'TEAMID1234.com.example.app',
        );

        final json = encodeReportJson(summary.toJson());
        for (final udid in plantedUdids) {
          expect(json, isNot(contains(udid)));
        }
        expect(json, isNot(contains(plantedTeamName)));
        expect(json, isNot(contains(plantedAppIdName)));
        expect(json, isNot(contains(base64.encode(plantedCertificate))));
      });
    }
  }

  test('returns null for non-CMS input', () {
    expect(readProfile(Uint8List.fromList(utf8.encode('nope'))), isNull);
    expect(readProfile(xmlPlist({'a': 1})), isNull);
    final truncated = mobileProvision(profilePlist(bundleId: 'x'));
    expect(readProfile(truncated.sublist(0, truncated.length ~/ 2)), isNull);
  });
}
