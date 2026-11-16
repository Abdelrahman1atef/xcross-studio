import 'package:studio_ext/src/shared/pods/pod_file_selector.dart';
import 'package:test/test.dart';

void main() {
  const selector = PodFileSelector();

  group('AC-046-13 PodFileSelector (T201)', () {
    test('**/* matches sources, headers, and separates other files', () {
      final files = [
        'Source/Core.m',
        'Source/Core.h',
        'Source/Helper.swift',
        'Source/CppUtil.cpp',
        'Source/Defs.inc',
        'Resources/icon.png',
        'Resources/View.xib',
        'Resources/Storyboard.storyboard',
        'Resources/Shader.metal',
        'config.json',
      ];

      final selection = selector.selectFiles(
        allRelativePaths: files,
        sourceFilesPatterns: ['**/*'],
      );

      expect(
        selection.sources,
        unorderedEquals([
          'Source/Core.m',
          'Source/Helper.swift',
          'Source/CppUtil.cpp',
        ]),
      );

      expect(
        selection.headers,
        unorderedEquals(['Source/Core.h', 'Source/Defs.inc']),
      );

      expect(
        selection.otherFiles,
        unorderedEquals([
          'Resources/icon.png',
          'Resources/View.xib',
          'Resources/Storyboard.storyboard',
          'Resources/Shader.metal',
          'config.json',
        ]),
      );
    });

    test('ios/Classes/* pattern matches code inside directory', () {
      final files = [
        'ios/Classes/FlutterSoundPlugin.m',
        'ios/Classes/FlutterSoundPlugin.h',
        'ios/Classes/Track.swift',
        'ios/Classes/README.md',
        'android/Classes/Other.java',
      ];

      final selection = selector.selectFiles(
        allRelativePaths: files,
        sourceFilesPatterns: ['ios/Classes/*'],
      );

      expect(
        selection.sources,
        unorderedEquals([
          'ios/Classes/FlutterSoundPlugin.m',
          'ios/Classes/Track.swift',
        ]),
      );
      expect(
        selection.headers,
        unorderedEquals(['ios/Classes/FlutterSoundPlugin.h']),
      );
      expect(selection.otherFiles, unorderedEquals(['ios/Classes/README.md']));
    });

    test(
      'directory pattern without wildcards appends default extensions for direct children only',
      () {
        final files = [
          'Classes/Root.m',
          'Classes/Root.h',
          'Classes/Sub/Nested.m',
          'Classes/Other.txt',
        ];

        final selection = selector.selectFiles(
          allRelativePaths: files,
          sourceFilesPatterns: ['Classes'],
        );

        // Direct children only
        expect(selection.sources, unorderedEquals(['Classes/Root.m']));
        expect(selection.headers, unorderedEquals(['Classes/Root.h']));
        expect(selection.otherFiles, isEmpty);
      },
    );

    test(
      'case-insensitive matching on Linux preserves original casing of file names',
      () {
        final files = [
          'ios/Classes/MixedCaseFile.M',
          'ios/Classes/HeaderFile.H',
          'ios/Classes/SWIFTFILE.SWIFT',
        ];

        final selection = selector.selectFiles(
          allRelativePaths: files,
          sourceFilesPatterns: ['ios/classes/*.{m,h,swift}'],
        );

        expect(
          selection.sources,
          unorderedEquals([
            'ios/Classes/MixedCaseFile.M',
            'ios/Classes/SWIFTFILE.SWIFT',
          ]),
        );
        expect(
          selection.headers,
          unorderedEquals(['ios/Classes/HeaderFile.H']),
        );
      },
    );

    test('brace expansion supports nested braces and comma lists', () {
      final files = [
        'src/c/util.c',
        'src/cpp/math.cpp',
        'src/objc/view.mm',
        'src/other/test.py',
      ];

      final selection = selector.selectFiles(
        allRelativePaths: files,
        sourceFilesPatterns: ['src/{c,cpp,objc}/*.{c,{cpp,mm}}'],
      );

      expect(
        selection.sources,
        unorderedEquals([
          'src/c/util.c',
          'src/cpp/math.cpp',
          'src/objc/view.mm',
        ]),
      );
    });

    test('preserve_paths selects extra files such as module.modulemap', () {
      final files = [
        'Sources/code.m',
        'GoogleMLKit/module.modulemap',
        'README.md',
      ];

      final selection = selector.selectFiles(
        allRelativePaths: files,
        sourceFilesPatterns: ['Sources/*.m'],
        preservePathsPatterns: ['GoogleMLKit/module.modulemap'],
      );

      expect(selection.sources, unorderedEquals(['Sources/code.m']));
      expect(
        selection.preservePaths,
        unorderedEquals(['GoogleMLKit/module.modulemap']),
      );
    });

    test('exclude_files filters out specified patterns', () {
      final files = [
        'Classes/Active.m',
        'Classes/Excluded.m',
        'Classes/Active.h',
      ];

      final selection = selector.selectFiles(
        allRelativePaths: files,
        sourceFilesPatterns: ['Classes/*'],
        excludeFilesPatterns: ['Classes/Excluded.m'],
      );

      expect(selection.sources, unorderedEquals(['Classes/Active.m']));
      expect(selection.headers, unorderedEquals(['Classes/Active.h']));
    });

    test(
      'throws PodFileSelectionException when source_files matches nothing',
      () {
        final files = ['other/file.txt'];

        expect(
          () => selector.selectFiles(
            allRelativePaths: files,
            sourceFilesPatterns: ['Classes/*.m'],
          ),
          throwsA(
            isA<PodFileSelectionException>().having(
              (e) => e.message,
              'message',
              contains('source_files matched no file'),
            ),
          ),
        );
      },
    );
  });
}
