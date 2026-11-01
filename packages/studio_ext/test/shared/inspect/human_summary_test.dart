import 'dart:io';

import 'package:studio_ext/src/shared/inspect/human_summary.dart';
import 'package:test/test.dart';

import '../../support/fixture_builder.dart';
import '../../support/inspect_helpers.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('summary_'));
  tearDown(() => temp.deleteSync(recursive: true));

  Map<String, String> markers(String summary) => {
    for (final line in summary.split('\n').skip(1))
      if (line.startsWith('✔') || line.startsWith('✖'))
        line.substring(2, 23).trim(): line.substring(0, 1),
  };

  const labels = [
    'signed',
    'provisioning profile',
    'push entitlement',
    'associated domains',
    'icon',
    'launch screen',
    'frameworks',
  ];

  test('AC-001-7 ✔/✖ summary without secrets', () {
    final unsigned = renderHumanSummary(
      inspectPath(unsignedV209().writeIpa(temp, 'unsigned_v209.ipa')),
    );
    expect(
      unsigned.split('\n').first,
      'unsigned_v209.ipa  com.example.fixture 1.0.0 (1), iOS 13.0+',
    );
    expect(markers(unsigned).keys, labels);
    expect(markers(unsigned), {
      'signed': '✖',
      'provisioning profile': '✖',
      'push entitlement': '✖',
      'associated domains': '✖',
      'icon': '✖',
      'launch screen': '✖',
      'frameworks': '✔',
    });
    expect(unsigned, contains('not signed (no _CodeSignature)'));
    expect(unsigned, contains('UILaunchScreen is empty'));
    expect(unsigned, contains('3 (App, Flutter, libpath_provider_foundation)'));
    expect(unsigned.trimRight().split('\n').last, startsWith('2 issues'));

    final push = renderHumanSummary(
      inspectPath(adhocPush().writeApp(temp, directoryName: 'adhoc_push.app')),
    );
    expect(markers(push)['signed'], '✔');
    expect(markers(push)['push entitlement'], '✔');
    expect(push, contains('aps-environment = development'));
    expect(push, contains('2 domains'));
    expect(push, contains('AppIcon60x60 (2 files)'));
    expect(push, contains('loose PNG (not shown by iOS)'));

    final profile = renderHumanSummary(
      inspectPath(profileAppex().writeIpa(temp, 'profile_appex.ipa')),
    );
    expect(markers(profile)['signed'], '✔');
    expect(profile, contains('certificate · team TEAMID1234'));
    expect(markers(profile)['provisioning profile'], '✔');
    expect(profile, contains('development · team TEAMID1234 · 3 devices'));
    expect(markers(profile)['launch screen'], '✔');

    for (final summary in [unsigned, push, profile]) {
      for (final udid in plantedUdids) {
        expect(summary, isNot(contains(udid)));
      }
      expect(summary, isNot(contains(plantedApiKey)));
      expect(summary, isNot(contains('11111111-2222')));
    }
  });

  test('push granted only by the profile is called out', () {
    final files = Map.of(profileAppex().files);
    files['Runner'] = machO(
      signature: codeSignature(teamId: 'TEAMID1234', cms: CmsBlob.signed),
    );
    final summary = renderHumanSummary(
      inspectPath(FixtureBundle('Runner.app', files).writeIpa(temp, 'a.ipa')),
    );
    expect(summary, contains('missing (profile grants it)'));
  });
}
