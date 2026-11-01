// studio: 004 — LaunchScreen.storyboard → what UILaunchScreen can show.
import 'package:studio_ext/shared/assets/asset_catalog_compiler.dart';
import 'package:studio_ext/shared/assets/launch_storyboard.dart';
import 'package:test/test.dart';

import '../../support/catalog_fixture.dart';

String _storyboard({required String subviews, String background = ''}) =>
    '''
<?xml version="1.0" encoding="UTF-8"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" launchScreen="YES" initialViewController="vc">
  <scenes>
    <scene sceneID="s">
      <objects>
        <viewController id="vc" sceneMemberID="viewController">
          <view key="view" contentMode="scaleToFill" id="root">
            <subviews>$subviews</subviews>
            $background
          </view>
        </viewController>
      </objects>
    </scene>
  </scenes>
  <resources>
    <systemColor name="systemTealColor">
      <color red="0.19" green="0.69" blue="0.78" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
    </systemColor>
  </resources>
</document>
''';

void main() {
  test('AC-004-2 Flutter template: white background, LaunchImage centred', () {
    final spec = LaunchStoryboard.parse(flutterLaunchStoryboard);
    expect(spec.background, const CatalogColor(red: 1, green: 1, blue: 1));
    expect(spec.backgroundColorName, isNull);
    expect(spec.imageName, 'LaunchImage');
    expect(spec.backgroundImageName, isNull);
    expect(spec.approximations, isEmpty);
  });

  test('AC-004-2 flutter_native_splash shape: background image plus '
      'centred image, explicit colour', () {
    final spec = LaunchStoryboard.parse(
      _storyboard(
        subviews: '''
          <imageView contentMode="scaleToFill" image="LaunchBackground" id="bg"/>
          <imageView contentMode="scaleAspectFit" image="LaunchImage" id="img"/>
        ''',
        background:
            '<color key="backgroundColor" red="0.2" green="0.4" blue="0.6" '
            'alpha="1" colorSpace="custom" customColorSpace="displayP3"/>',
      ),
    );
    expect(spec.backgroundImageName, 'LaunchBackground');
    expect(spec.imageName, 'LaunchImage');
    expect(
      spec.background,
      const CatalogColor(red: 0.2, green: 0.4, blue: 0.6, displayP3: true),
    );
    expect(spec.approximations, isEmpty);
  });

  test('system, white-component and named colours', () {
    LaunchScreenSpec withColor(String color) => LaunchStoryboard.parse(
      _storyboard(
        subviews: '',
        background: '<color key="backgroundColor" $color/>',
      ),
    );
    expect(
      withColor('systemColor="systemBackgroundColor"').background,
      LaunchStoryboard.systemColors['systemBackgroundColor'],
    );
    expect(
      withColor('systemColor="systemTealColor"').background,
      const CatalogColor(red: 0.19, green: 0.69, blue: 0.78),
    );
    expect(
      withColor('white="0" alpha="1" colorSpace="calibratedWhite"').background,
      const CatalogColor(red: 0, green: 0, blue: 0),
    );
    final named = withColor('name="SplashColor"');
    expect(named.backgroundColorName, 'SplashColor');
    expect(named.background, isNull);
  });

  test('AC-004-4 what UILaunchScreen cannot show is listed', () {
    final spec = LaunchStoryboard.parse(
      _storyboard(
        subviews: '''
          <imageView contentMode="center" image="Logo" id="a"/>
          <imageView contentMode="center" image="Badge" id="b"/>
          <label text="Welcome" id="c"/>
          <activityIndicatorView id="d"/>
        ''',
      ),
    );
    expect(spec.imageName, 'Logo');
    expect(spec.approximations, [
      'image "Badge"',
      'label "Welcome"',
      'a activityIndicatorView',
    ]);
  });

  test('AC-004-4 unreadable storyboards are a FormatException', () {
    expect(
      () => LaunchStoryboard.parse('<document><broken'),
      throwsFormatException,
    );
    expect(
      () => LaunchStoryboard.parse('<plist version="1.0"/>'),
      throwsFormatException,
    );
    expect(
      () => LaunchStoryboard.parse('<document><scenes/></document>'),
      throwsFormatException,
    );
  });
}
