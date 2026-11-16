import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:studio_ext/src/shared/pods/pod_spec_repo.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late Directory repoDir;
  const resolver = PodSpecRepoResolver();

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pod-spec-repo-test-');
    repoDir = Directory(p.join(tempDir.path, 'MySpecs'))
      ..createSync(recursive: true);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('AC-046-22 lookupSpec finds sharded json podspec', () {
    const pod = 'CustomJsonPod';
    const version = '1.2.0';
    final shards = PodSpecRepoResolver.shardFor(pod);
    final specDir = Directory(
      p.join(
        repoDir.path,
        'Specs',
        shards[0],
        shards[1],
        shards[2],
        pod,
        version,
      ),
    )..createSync(recursive: true);

    File(p.join(specDir.path, '$pod.podspec.json')).writeAsStringSync('''
{
  "name": "$pod",
  "version": "$version",
  "source_files": "ios/Classes/**/*",
  "dependencies": {
    "GoogleUtilities": ["~> 7.10"]
  }
}
''');

    final result = resolver.lookupSpec(
      repoDir: repoDir,
      repoUrl: 'https://github.com/my-org/Specs.git',
      pod: pod,
      version: version,
    );

    expect(result, isNotNull);
    expect(result!.pod, pod);
    expect(result.version, version);
    expect(result.jsonSpec, isNotNull);
    expect(result.jsonSpec!['name'], pod);
    expect(result.hasUnreadLines, isFalse);
    expect(result.unreadWarning, isNull);
  });

  test(
    'AC-046-22 lookupSpec finds Ruby podspec and parses subset with unread lines',
    () {
      const pod = 'CustomRubyPod';
      const version = '2.0.0';
      final specDir = Directory(p.join(repoDir.path, pod, version))
        ..createSync(recursive: true);

      File(p.join(specDir.path, '$pod.podspec')).writeAsStringSync('''
Pod::Spec.new do |s|
  s.name             = '$pod'
  s.version          = '$version'
  s.summary          = 'Custom Ruby Pod'
  s.source_files     = 'src/**/*.{h,m}'
  s.frameworks       = 'Security', 'UIKit'
  s.dependency 'nanopb', '~> 3.30910'
  s.prepare_command  = 'ruby generate_bindings.rb'
  s.header_mappings_dir = 'src/include'
end
''');

      final result = resolver.lookupSpec(
        repoDir: repoDir,
        repoUrl: 'https://github.com/my-org/Specs.git',
        pod: pod,
        version: version,
      );

      expect(result, isNotNull);
      expect(result!.pod, pod);
      expect(result.version, version);
      expect(result.podspec, isNotNull);
      expect(result.podspec!.name, pod);
      expect(result.podspec!.version, version);
      expect(result.podspec!.sourceFiles, ['src/**/*.{h,m}']);
      expect(result.podspec!.frameworks, containsAll(['Security', 'UIKit']));
      expect(
        result.podspec!.dependencies.map((d) => d.name),
        contains('nanopb'),
      );

      // Unread lines collected
      expect(result.hasUnreadLines, isTrue);
      expect(
        result.unreadLines,
        contains("s.prepare_command  = 'ruby generate_bindings.rb'"),
      );
      expect(
        result.unreadLines,
        contains("s.header_mappings_dir = 'src/include'"),
      );
      expect(result.unreadWarning, contains('pod.podspec_unread'));
    },
  );
}
