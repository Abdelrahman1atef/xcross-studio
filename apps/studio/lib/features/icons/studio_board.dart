// Feature 026: what the studio's two tabs share, so each can show the other's
// work and one action can write both. Each tab keeps its own design and preview
// process, and publishes its images and actions here.
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'device_gallery.dart';
import 'studio_controls.dart';
import 'studio_model.dart';

class StudioBoard extends ChangeNotifier {
  /// The icon's latest images, by preview variant.
  Map<String, Uint8List> iconImages = const {};
  String iconShape = 'squircle';

  /// The icon's source as a PNG, the splash's first logo (AC-026-14).
  String? iconSource;

  /// The splash's latest images, by preview variant; empty without a logo.
  Map<String, Uint8List> splashImages = const {};
  SplashStudioDesign? splash;

  /// Each answers whether it did what it was asked.
  Future<bool> Function(String project)? writeIcon;
  Future<bool> Function(String project)? writeSplash;
  Future<bool> Function(String folder)? exportIcon;
  Future<bool> Function(String folder)? exportSplash;

  void changed() => notifyListeners();

  /// What the frames show, from the two designs as they are now.
  GalleryContent content({String name = 'App'}) {
    final design = splash;
    final images = splashImages;
    final background = StudioColor.parse(design?.background);
    return GalleryContent(
      name: name,
      icon: iconImages['full'],
      adaptiveIcon: iconImages['adaptive'],
      shape: iconShape,
      background: background ?? Colors.white,
      darkBackground: StudioColor.parse(design?.darkBackground),
      android12Background: StudioColor.parse(design?.android12IconBackground),
      darkAndroid12Background: StudioColor.parse(
        design?.darkAndroid12IconBackground,
      ),
      logo: images['logo'],
      darkLogo: images['darkLogo'],
      ipadLogo: images['ipadLogo'],
      darkIpadLogo: images['darkIpadLogo'],
      androidLogo: images['androidLogo'] ?? images['logo'],
      darkAndroidLogo: images['darkAndroidLogo'] ?? images['darkLogo'],
      android12: images['android12'],
      darkAndroid12: images['darkAndroid12'],
      branding: images['branding'],
      darkBranding: images['darkBranding'],
      brandingWidth: design?.brandingWidth ?? 180,
      brandingBottom: design?.brandingBottom ?? 32,
      notes: [
        if (iconImages.isEmpty)
          'Choose a source on the App icon tab to see it.',
        if (design?.logo == null)
          'Pick a logo on the Splash screen tab to see it.',
      ],
    );
  }
}
