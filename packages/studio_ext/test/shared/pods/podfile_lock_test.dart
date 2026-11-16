import 'package:studio_ext/src/shared/pods/podfile_lock.dart';
import 'package:test/test.dart';

void main() {
  test('AC-046-2 parses every Podfile.lock section', () {
    final lock = PodfileLock.parse('''
PODS:
  - "A/Subspec (1.2.3)":
    - "B/Core (~> 2.0)"
  - B/Core (2.0.4)
DEPENDENCIES:
  - "A/Subspec (= 1.2.3)"
SPEC REPOS:
  trunk:
    - A
  "https://example.com/specs.git":
    - B
EXTERNAL SOURCES:
  A:
    :path: ".symlinks/plugins/a/ios"
CHECKOUT OPTIONS:
  B:
    :git: "https://example.com/b.git"
    :commit: abc123
SPEC CHECKSUMS:
  A: 123abc
  B: def456
PODFILE CHECKSUM: 987abc
COCOAPODS: 1.16.2
''');
    expect(lock.pods['A/Subspec']!.version, '1.2.3');
    expect(lock.pods['A/Subspec']!.dependencies, ['B/Core (~> 2.0)']);
    expect(lock.pods['B/Core']!.version, '2.0.4');
    expect(lock.dependencies, ['A/Subspec (= 1.2.3)']);
    expect(lock.specRepos['trunk'], ['A']);
    expect(lock.specRepos['https://example.com/specs.git'], ['B']);
    expect(lock.externalSources['A']![':path'], '.symlinks/plugins/a/ios');
    expect(lock.checkoutOptions['B']![':commit'], 'abc123');
    expect(lock.specChecksums['A'], '123abc');
    expect(lock.podfileChecksum, '987abc');
    expect(lock.cocoapodsVersion, '1.16.2');
  });

  test('AC-046-2 accepts empty sections', () {
    final lock = PodfileLock.parse('''
PODS:
DEPENDENCIES:
SPEC REPOS:
EXTERNAL SOURCES:
CHECKOUT OPTIONS:
SPEC CHECKSUMS:
''');
    expect(lock.pods, isEmpty);
    expect(lock.specRepos, isEmpty);
    expect(lock.checkoutOptions, isEmpty);
  });
}
