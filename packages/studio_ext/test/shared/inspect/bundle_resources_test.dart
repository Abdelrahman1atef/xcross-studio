import 'dart:typed_data';

import 'package:studio_ext/src/shared/inspect/bundle_resources.dart';
import 'package:studio_ext/src/shared/inspect/inspect_report.dart';
import 'package:test/test.dart';

import '../../support/fixture_builder.dart';
import '../../support/memory_source.dart';

void main() {
  (Resources, List<String>) read(
    Map<String, Object?> info,
    Map<String, Uint8List> files,
  ) {
    final issues = <Issue>[];
    final resources = readResources(MemorySource(files), info, issues);
    return (resources, [for (final i in issues) i.code]);
  }

  group('AC-001-4 icons', () {
    test('resolves @2x/@3x/~ipad variants and explicit .png names', () {
      final (resources, codes) = read(
        {
          'CFBundleIcons': {
            'CFBundlePrimaryIcon': {
              'CFBundleIconFiles': ['Icon', 'Other.png'],
            },
          },
          'CFBundleIcons~ipad': {
            'CFBundlePrimaryIcon': {
              'CFBundleIconFiles': ['Icon'],
            },
          },
          'CFBundleIconFile': 'Legacy',
        },
        {
          'Icon@2x.png': fakePng,
          'Icon@3x~ipad.png': fakePng,
          'Other.png': fakePng,
          'Legacy.png': fakePng,
          'Sub/Icon@2x.png': fakePng,
          'IconX@2x.png': fakePng,
        },
      );
      expect(
        resources.icons.declared.map((i) => '${i.set}:${i.name}:${i.files}'),
        [
          'CFBundleIconFile:Legacy:[Legacy.png]',
          'CFBundleIcons:Icon:[Icon@2x.png, Icon@3x~ipad.png]',
          'CFBundleIcons:Other.png:[Other.png]',
          'CFBundleIcons~ipad:Icon:[Icon@2x.png, Icon@3x~ipad.png]',
        ],
      );
      expect(codes, isNot(contains('inspect.no_icon')));
    });

    test('no icon declared and no Assets.car', () {
      final (resources, codes) = read(
        {'UILaunchScreen': <String, Object>{}},
        {'Runner': fakePng},
      );
      expect(resources.icons.declared, isEmpty);
      expect(codes, contains('inspect.no_icon'));
    });

    test('asset-catalog icon name with Assets.car is not "no icon"', () {
      final (_, codes) = read(
        {
          'CFBundleIcons': {
            'CFBundlePrimaryIcon': {'CFBundleIconName': 'AppIcon'},
          },
          'UILaunchScreen': {'UIColorName': 'Bg'},
        },
        {'Assets.car': Uint8List(4)},
      );
      expect(codes, isEmpty);
    });
  });

  group('AC-001-4 launch screen', () {
    test('missing launch image without Assets.car', () {
      final (resources, codes) = read({
        'UILaunchScreen': {'UIImageName': 'Splash'},
      }, {});
      expect(resources.launchScreen.image!.source, LaunchImageSource.missing);
      expect(codes, contains('inspect.launch_image_missing'));
    });

    test('compiled storyboard in Base.lproj counts as present', () {
      final (resources, codes) = read(
        {'UILaunchStoryboardName': 'LaunchScreen'},
        {'Base.lproj/LaunchScreen.storyboardc/Info.plist': Uint8List(1)},
      );
      expect(resources.launchScreen.kind, LaunchScreenKind.storyboard);
      expect(resources.launchScreen.storyboard!.compiledPresent, isTrue);
      expect(resources.storyboards, ['Base.lproj/LaunchScreen.storyboardc']);
      expect(codes, isNot(contains('inspect.launch_storyboard_missing')));
    });

    test('unknown Info.plist skips declaration-based issues', () {
      final issues = <Issue>[];
      readResources(MemorySource({}), null, issues);
      expect(issues, isEmpty);
    });
  });
}
