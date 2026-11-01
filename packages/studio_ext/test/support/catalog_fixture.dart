// studio: 004 — asset catalog fixtures shaped like Flutter's iOS template.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'png_builder.dart';

/// Flutter template app icon slots: `(idiom, size, scale)`.
const flutterIconSlots = [
  ('iphone', 20.0, 2),
  ('iphone', 20.0, 3),
  ('iphone', 29.0, 1),
  ('iphone', 29.0, 2),
  ('iphone', 29.0, 3),
  ('iphone', 40.0, 2),
  ('iphone', 40.0, 3),
  ('iphone', 60.0, 2),
  ('iphone', 60.0, 3),
  ('ipad', 20.0, 1),
  ('ipad', 20.0, 2),
  ('ipad', 29.0, 1),
  ('ipad', 29.0, 2),
  ('ipad', 40.0, 1),
  ('ipad', 40.0, 2),
  ('ipad', 76.0, 1),
  ('ipad', 76.0, 2),
  ('ipad', 83.5, 2),
  ('ios-marketing', 1024.0, 1),
];

String _size(double points) =>
    points == points.roundToDouble() ? '${points.toInt()}' : '$points';

void writeJson(String path, Object json) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));
}

void writeBytes(String path, Uint8List bytes) {
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(bytes);
}

/// `Assets.xcassets` with Flutter's AppIcon set (every slot, plus the
/// 1024 App Store icon) and LaunchImage at 1x/2x/3x.
String writeFlutterCatalog(String root) {
  final catalog = '$root/Assets.xcassets';
  writeJson('$catalog/Contents.json', {
    'info': {'version': 1, 'author': 'xcode'},
  });
  final icons = <Map<String, Object>>[];
  for (final (idiom, points, scale) in flutterIconSlots) {
    final file = 'Icon-App-${_size(points)}x${_size(points)}@${scale}x.png';
    icons.add({
      'size': '${_size(points)}x${_size(points)}',
      'idiom': idiom,
      'filename': file,
      'scale': '${scale}x',
    });
    final pixels = (points * scale).round();
    // The 1024 icon stays small: it is never decoded (marketing only).
    writeBytes(
      '$catalog/AppIcon.appiconset/$file',
      idiom == 'ios-marketing'
          ? solidPng(1, 1, (0, 0, 0, 255))
          : gradientPng(pixels, pixels),
    );
  }
  writeJson('$catalog/AppIcon.appiconset/Contents.json', {
    'images': icons,
    'info': {'version': 1, 'author': 'xcode'},
  });
  writeJson('$catalog/LaunchImage.imageset/Contents.json', {
    'images': [
      for (final scale in [1, 2, 3])
        {
          'idiom': 'universal',
          'filename': scale == 1
              ? 'LaunchImage.png'
              : 'LaunchImage@${scale}x.png',
          'scale': '${scale}x',
        },
    ],
    'info': {'version': 1, 'author': 'xcode'},
  });
  for (final scale in [1, 2, 3]) {
    writeBytes(
      '$catalog/LaunchImage.imageset/'
      '${scale == 1 ? 'LaunchImage.png' : 'LaunchImage@${scale}x.png'}',
      gradientPng(4 * scale, 3 * scale),
    );
  }
  return catalog;
}

/// Flutter's `ios/Runner/Base.lproj/LaunchScreen.storyboard` template.
const flutterLaunchStoryboard = '''
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<document type="com.apple.InterfaceBuilder3.CocoaTouch.Storyboard.XIB" version="3.0" toolsVersion="12121" systemVersion="16G29" targetRuntime="iOS.CocoaTouch" propertyAccessControl="none" useAutolayout="YES" launchScreen="YES" colorMatched="YES" initialViewController="01J-lp-oVM">
    <dependencies>
        <deployment identifier="iOS"/>
        <plugIn identifier="com.apple.InterfaceBuilder.IBCocoaTouchPlugin" version="12089"/>
    </dependencies>
    <scenes>
        <scene sceneID="EHf-IW-A2E">
            <objects>
                <viewController id="01J-lp-oVM" sceneMemberID="viewController">
                    <layoutGuides>
                        <viewControllerLayoutGuide type="top" id="Ydg-fD-yQy"/>
                        <viewControllerLayoutGuide type="bottom" id="xbc-2k-c8Z"/>
                    </layoutGuides>
                    <view key="view" contentMode="scaleToFill" id="Ze5-6b-2t3">
                        <autoresizingMask key="autoresizingMask" widthSizable="YES" heightSizable="YES"/>
                        <subviews>
                            <imageView opaque="NO" clipsSubviews="YES" multipleTouchEnabled="YES" contentMode="center" image="LaunchImage" translatesAutoresizingMaskIntoConstraints="NO" id="YRO-k0-Ey4">
                            </imageView>
                        </subviews>
                        <color key="backgroundColor" red="1" green="1" blue="1" alpha="1" colorSpace="custom" customColorSpace="sRGB"/>
                        <constraints>
                            <constraint firstItem="YRO-k0-Ey4" firstAttribute="centerX" secondItem="Ze5-6b-2t3" secondAttribute="centerX" id="1a2-6s-vTC"/>
                            <constraint firstItem="YRO-k0-Ey4" firstAttribute="centerY" secondItem="Ze5-6b-2t3" secondAttribute="centerY" id="4X2-HB-R7a"/>
                        </constraints>
                    </view>
                </viewController>
                <placeholder placeholderIdentifier="IBFirstResponder" id="iYj-Kq-Ea1" userLabel="First Responder" sceneMemberID="firstResponder"/>
            </objects>
            <point key="canvasLocation" x="53" y="375"/>
        </scene>
    </scenes>
    <resources>
        <image name="LaunchImage" width="168" height="185"/>
    </resources>
</document>
''';
