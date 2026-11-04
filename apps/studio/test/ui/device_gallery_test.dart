// Feature 026: the icon and splash on every screen.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xcross_studio/design_system/design_system.dart';
import 'package:xcross_studio/features/icons/device_catalog.dart';
import 'package:xcross_studio/features/icons/device_gallery.dart';
import 'package:xcross_studio/src/cli/xcross_events.dart';

/// A 1×1 PNG. Distinct copies, so a test can tell which one a frame draws.
Uint8List _png() => base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNgYPgPAAEDAQAIicLsAAAAAElFTkSuQmCC',
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(1800, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: xDarkTheme(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pump();
}

GalleryFilters _only(
  Set<DeviceFamily> families, {
  bool splash = true,
  bool home = false,
}) => GalleryFilters()
  ..families.retainWhere(families.contains)
  ..splash = splash
  ..home = home;

/// The image bytes each frame of [screen] draws, in tree order.
List<Uint8List> _drawn(WidgetTester tester) => [
  for (final image in tester.widgetList<Image>(find.byType(Image)))
    (image.image as MemoryImage).bytes,
];

void main() {
  group('AC-026-8 the list of screens', () {
    Iterable<DeviceScreen> of(DeviceFamily family) =>
        deviceScreens.where((screen) => screen.family == family);

    test('every distinct iPhone screen, with its scale and safe areas', () {
      final sizes = {
        for (final screen in of(DeviceFamily.iPhone))
          '${screen.width.round()}x${screen.height.round()}@${screen.scale}',
      };
      expect(sizes, {
        '320x568@2',
        '375x667@2',
        '414x736@3',
        '375x812@3',
        '390x844@3',
        '393x852@3',
        '402x874@3',
        '414x896@2',
        '414x896@3',
        '420x912@3',
        '428x926@3',
        '430x932@3',
        '440x956@3',
      });
      for (final screen in of(DeviceFamily.iPhone)) {
        expect(screen.safeTop, greaterThan(0), reason: screen.name);
        expect(screen.android, isFalse);
      }
      // Newest first in no way changes what a smaller phone is: it is listed.
      expect(of(DeviceFamily.iPhone).first.width, 320);
    });

    test('every distinct iPad screen', () {
      expect(
        {
          for (final screen in of(DeviceFamily.iPad))
            '${screen.width.round()}x${screen.height.round()}',
        },
        {
          '744x1133',
          '768x1024',
          '810x1080',
          '820x1180',
          '834x1112',
          '834x1194',
          '834x1210',
          '1024x1366',
          '1032x1376',
        },
      );
    });

    test('Android phones, tablets and foldables, in dp', () {
      expect(of(DeviceFamily.androidPhone), isNotEmpty);
      expect(
        of(DeviceFamily.androidTablet).map((screen) => screen.name),
        containsAll(['Foldable, closed', 'Foldable, open', 'Tablet']),
      );
      for (final screen in [
        ...of(DeviceFamily.androidPhone),
        ...of(DeviceFamily.androidTablet),
      ]) {
        expect(screen.android, isTrue, reason: screen.name);
        expect(screen.sizeLabel, endsWith('dp'));
      }
    });

    test('no screen is listed twice', () {
      final keys = deviceScreens.map((s) => '${s.name} ${s.sizeLabel}');
      expect(keys.toSet().length, keys.length);
    });
  });

  group('AC-026-9 true proportions', () {
    testWidgets('a frame has its device\'s shape, and sizes compare truly', (
      tester,
    ) async {
      final phone = deviceScreens.firstWhere((s) => s.width == 320);
      final pad = deviceScreens.firstWhere((s) => s.width == 1032);
      await _pump(
        tester,
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DeviceFrame(
              key: const ValueKey('phone'),
              screen: phone,
              content: const GalleryContent(),
            ),
            DeviceFrame(
              key: const ValueKey('pad'),
              screen: pad,
              content: const GalleryContent(),
            ),
          ],
        ),
      );
      Size inner(String key) {
        final size = tester.getSize(find.byKey(ValueKey(key)));
        // Less the bezel on each side.
        return Size(size.width - 6, size.height - 6);
      }

      expect(
        inner('phone').height / inner('phone').width,
        closeTo(568 / 320, 0.001),
      );
      expect(
        inner('pad').height / inner('pad').width,
        closeTo(1376 / 1032, 0.001),
      );
      expect(
        inner('pad').width / inner('phone').width,
        closeTo(1032 / 320, 0.001),
      );
    });

    testWidgets('the logo is at its true size against the screen', (
      tester,
    ) async {
      // 2 px per point: a 200 px image is 100 pt, on a 320 pt wide screen.
      final logo = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGNgYPgPAAEDAQAIicLsAAAAAElFTkSuQmCC',
      );
      final screen = deviceScreens.firstWhere((s) => s.width == 320);
      await _pump(
        tester,
        DeviceFrame(
          key: const ValueKey('frame'),
          screen: screen,
          content: GalleryContent(logo: logo),
        ),
      );
      await tester.runAsync(
        () => precacheImage(
          MemoryImage(logo, scale: 2),
          tester.element(find.byKey(const ValueKey('frame'))),
        ),
      );
      await tester.pump();
      final image = tester.getRect(find.byType(Image));
      // A 1 px image at 2 px per point is 0.5 pt, scaled like the rest.
      expect(image.width, closeTo(0.5 * DeviceFrame.pointScale, 0.001));
      expect(
        image.center.dx,
        closeTo(tester.getCenter(find.byKey(const ValueKey('frame'))).dx, 0.01),
      );
      expect(
        image.center.dy,
        closeTo(tester.getCenter(find.byKey(const ValueKey('frame'))).dy, 0.01),
      );
    });
  });

  group('AC-026-10 the filters', () {
    int frames(WidgetTester tester) =>
        find.byType(DeviceFrame).evaluate().length;

    testWidgets('family, splash or home, light or dark', (tester) async {
      final filters = _only({DeviceFamily.iPad});
      await _pump(
        tester,
        DeviceGallery(content: const GalleryContent(), filters: filters),
      );
      final pads = deviceScreens
          .where((s) => s.family == DeviceFamily.iPad)
          .length;
      expect(frames(tester), pads);

      await tester.tap(find.text('Home icon'));
      await tester.pump();
      expect(frames(tester), pads * 2, reason: 'splash and home');

      await tester.tap(find.text('Dark'));
      await tester.pump();
      expect(frames(tester), pads * 4, reason: 'and light and dark');

      await tester.tap(find.widgetWithText(FilterChip, 'iPhone'));
      await tester.pump();
      final phones = deviceScreens
          .where((s) => s.family == DeviceFamily.iPhone)
          .length;
      expect(frames(tester), (pads + phones) * 4);
    });

    testWidgets('one of light and dark, and of splash and home, stays on', (
      tester,
    ) async {
      final filters = _only({DeviceFamily.iPad});
      await _pump(
        tester,
        DeviceGallery(content: const GalleryContent(), filters: filters),
      );
      await tester.tap(find.widgetWithText(FilterChip, 'Light'));
      await tester.tap(find.widgetWithText(FilterChip, 'Splash'));
      await tester.pump();
      expect(filters.light, isTrue);
      expect(filters.splash, isTrue);
    });

    testWidgets('landscape swaps the sides', (tester) async {
      final filters = _only({DeviceFamily.iPhone});
      await _pump(
        tester,
        DeviceGallery(content: const GalleryContent(), filters: filters),
      );
      final upright = tester.getSize(find.byType(DeviceFrame).first);
      await tester.tap(find.text('Landscape'));
      await tester.pump();
      final sideways = tester.getSize(find.byType(DeviceFrame).first);
      expect(sideways.width, closeTo(upright.height, 0.001));
      expect(sideways.height, closeTo(upright.width, 0.001));
    });

    testWidgets('safe area guides show on a frame', (tester) async {
      final filters = _only({DeviceFamily.iPhone});
      await _pump(
        tester,
        DeviceGallery(content: const GalleryContent(), filters: filters),
      );
      Finder guides() => find.byWidgetPredicate(
        (widget) =>
            widget is ColoredBox && widget.color == const Color(0x55FF9F0A),
      );
      expect(guides(), findsNothing);
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(guides(), findsWidgets);
    });

    testWidgets('frames say which screen they are', (tester) async {
      await _pump(
        tester,
        DeviceGallery(
          content: const GalleryContent(),
          filters: _only({DeviceFamily.iPhone}),
        ),
      );
      expect(
        find.textContaining('iPhone Air\n420 × 912 pt @3x'),
        findsOneWidget,
      );
    });
  });

  group('AC-026-11 a custom size', () {
    Future<GalleryFilters> open(WidgetTester tester) async {
      final filters = _only({DeviceFamily.custom});
      await _pump(
        tester,
        DeviceGallery(content: const GalleryContent(), filters: filters),
      );
      return filters;
    }

    testWidgets('adds a frame of that shape', (tester) async {
      await open(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Width'), '600');
      await tester.enterText(find.widgetWithText(TextField, 'Height'), '1000');
      await tester.tap(find.widgetWithText(XButton, 'Add a screen'));
      await tester.pump();
      expect(find.byType(DeviceFrame), findsOneWidget);
      expect(find.textContaining('600 × 1000 pt'), findsOneWidget);
    });

    for (final (width, height) in const [
      ('50', '800'),
      ('800', '9000'),
      ('', '800'),
      ('wide', '800'),
    ]) {
      testWidgets('refuses "$width" × "$height" and says why', (tester) async {
        await open(tester);
        await tester.enterText(find.widgetWithText(TextField, 'Width'), width);
        await tester.enterText(
          find.widgetWithText(TextField, 'Height'),
          height,
        );
        await tester.tap(find.widgetWithText(XButton, 'Add a screen'));
        await tester.pump();
        expect(find.byType(DeviceFrame), findsNothing);
        expect(find.textContaining('from 100 to 5000'), findsOneWidget);
      });
    }

    testWidgets('can be drawn as Android', (tester) async {
      await open(tester);
      await tester.tap(find.text('Android').last);
      await tester.pump();
      await tester.enterText(find.widgetWithText(TextField, 'Width'), '600');
      await tester.enterText(find.widgetWithText(TextField, 'Height'), '1000');
      await tester.tap(find.widgetWithText(XButton, 'Add a screen'));
      await tester.pump();
      expect(find.textContaining('600 × 1000 dp'), findsOneWidget);
    });
  });

  group('AC-026-12 each platform draws what it really shows', () {
    final logo = _png();
    final androidLogo = _png();
    final android12 = _png();
    final branding = _png();
    final content = GalleryContent(
      logo: logo,
      androidLogo: androidLogo,
      android12: android12,
      branding: branding,
    );
    DeviceScreen first(DeviceFamily family) =>
        deviceScreens.firstWhere((s) => s.family == family);

    testWidgets('iOS: the launch image only, its branding is inside it', (
      tester,
    ) async {
      await _pump(
        tester,
        DeviceFrame(screen: first(DeviceFamily.iPhone), content: content),
      );
      expect(_drawn(tester), [same(logo)]);
    });

    testWidgets('Android 11 and older: the logo without branding, branding '
        'near the bottom', (tester) async {
      await _pump(
        tester,
        DeviceFrame(
          screen: first(DeviceFamily.androidPhone),
          content: content,
          android12: false,
        ),
      );
      expect(_drawn(tester), [same(androidLogo), same(branding)]);
    });

    testWidgets('Android 12 and newer: its own icon and the branding', (
      tester,
    ) async {
      await _pump(
        tester,
        DeviceFrame(screen: first(DeviceFamily.androidPhone), content: content),
      );
      expect(_drawn(tester), [same(android12), same(branding)]);
    });

    group('AC-026-30 Android 12 shows its icon through a circle', () {
      Size circle(WidgetTester tester) =>
          tester.getSize(find.byKey(const ValueKey('android12-circle')));

      testWidgets('192 dp across, masked', (tester) async {
        await _pump(
          tester,
          DeviceFrame(
            screen: first(DeviceFamily.androidPhone),
            content: content,
            scale: 1,
          ),
        );
        expect(circle(tester), const Size(192, 192));
        expect(find.byType(ClipOval), findsOneWidget);
      });

      testWidgets('160 dp across with an icon background', (tester) async {
        await _pump(
          tester,
          DeviceFrame(
            screen: first(DeviceFamily.androidPhone),
            content: const GalleryContent(android12Background: Colors.red),
            scale: 1,
          ),
        );
        expect(circle(tester), const Size(160, 160));
      });
    });

    testWidgets('dark uses the dark image and colour', (tester) async {
      final dark = _png();
      await _pump(
        tester,
        DeviceFrame(
          screen: first(DeviceFamily.iPhone),
          dark: true,
          content: GalleryContent(
            logo: logo,
            darkLogo: dark,
            background: Colors.white,
            darkBackground: const Color(0xFF101014),
          ),
        ),
      );
      expect(_drawn(tester), [same(dark)]);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is ColoredBox && widget.color == const Color(0xFF101014),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the home screen shows the icon', (tester) async {
      final icon = _png();
      final adaptive = _png();
      final both = GalleryContent(icon: icon, adaptiveIcon: adaptive);
      await _pump(
        tester,
        DeviceFrame(
          screen: first(DeviceFamily.iPhone),
          content: both,
          home: true,
        ),
      );
      expect(_drawn(tester), [same(icon)]);
      await _pump(
        tester,
        DeviceFrame(
          screen: first(DeviceFamily.androidPhone),
          content: both,
          home: true,
        ),
      );
      expect(_drawn(tester), [same(adaptive)]);
    });

    test('the splash report keeps what each platform holds', () {
      final report =
          XcrossEvent.tryParse(
                jsonEncode({
                  'v': 1,
                  'type': 'splash_check',
                  'ios': {
                    'background': '#FFFFFF',
                    'darkBackground': '#101014',
                    'logo': 'LaunchImage',
                  },
                  'android': {'background': '#000000', 'logo': 'splash_logo'},
                  'issues': <Object>[],
                  'errors': 0,
                }),
              )!
              as SplashCheckReport;
      expect(report.ios!.logo, 'LaunchImage');
      expect(report.ios!.darkBackground, '#101014');
      expect(report.android!.background, '#000000');
    });
  });

  group('AC-026-13 every icon size', () {
    testWidgets('each iOS slot, Android density and launcher shape', (
      tester,
    ) async {
      await _pump(
        tester,
        IconSizesSection(content: GalleryContent(icon: _png())),
      );
      expect(
        find.byType(Image),
        findsNWidgets(
          iosIconSizes.length +
              androidIconDensities.length +
              androidIconShapes.length,
        ),
      );
      expect(find.textContaining('83.5 pt @2x'), findsOneWidget);
      expect(find.textContaining('xxxhdpi'), findsOneWidget);
      expect(find.text('circle'), findsOneWidget);
    });

    testWidgets('leaves out iOS where another card shows it', (tester) async {
      await _pump(
        tester,
        IconSizesSection(content: GalleryContent(icon: _png()), ios: false),
      );
      expect(find.text('iOS'), findsNothing);
      expect(find.text('Android densities'), findsOneWidget);
    });
  });
}
