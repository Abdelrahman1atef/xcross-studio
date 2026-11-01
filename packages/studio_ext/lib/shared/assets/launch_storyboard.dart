// studio: 004 — turn an uncompilable `LaunchScreen.storyboard` into the
// `UILaunchScreen` dictionary iOS 14+ draws from Info.plist.
import 'package:studio_ext/shared/assets/asset_catalog_compiler.dart';
import 'package:xml/xml.dart';

/// What a launch storyboard shows, reduced to what `UILaunchScreen` can
/// draw: one background colour and one centred image.
final class LaunchScreenSpec {
  const LaunchScreenSpec({
    this.background,
    this.backgroundColorName,
    this.imageName,
    this.backgroundImageName,
    this.approximations = const [],
  });

  /// The main view's background colour (`null` when it names a catalog
  /// colour set, see [backgroundColorName]).
  final CatalogColor? background;

  /// A colour set from the asset catalog used as the background.
  final String? backgroundColorName;

  /// The centred image (`UIImageName`), an image set name.
  final String? imageName;

  /// A full-screen (scale-to-fill) image behind everything; `UILaunchScreen`
  /// can only show it when it is a single colour.
  final String? backgroundImageName;

  /// Elements `UILaunchScreen` cannot show (labels, extra images, …).
  final List<String> approximations;
}

/// Reads Interface Builder launch storyboards (and launch XIBs).
abstract final class LaunchStoryboard {
  static const white = CatalogColor(red: 1, green: 1, blue: 1);

  /// iOS system colours a launch screen commonly uses, light and dark.
  static const systemColors = {
    'systemBackgroundColor': CatalogColor(
      red: 1,
      green: 1,
      blue: 1,
      dark: CatalogColor(red: 0, green: 0, blue: 0),
    ),
    'systemGroupedBackgroundColor': CatalogColor(
      red: 0.949,
      green: 0.949,
      blue: 0.969,
      dark: CatalogColor(red: 0, green: 0, blue: 0),
    ),
    'secondarySystemBackgroundColor': CatalogColor(
      red: 0.949,
      green: 0.949,
      blue: 0.969,
      dark: CatalogColor(red: 0.110, green: 0.110, blue: 0.118),
    ),
    'whiteColor': white,
    'blackColor': CatalogColor(red: 0, green: 0, blue: 0),
    'groupTableViewBackgroundColor': CatalogColor(
      red: 0.937,
      green: 0.937,
      blue: 0.957,
    ),
    'clearColor': CatalogColor(red: 0, green: 0, blue: 0, alpha: 0),
  };

  static const _fillModes = {'scaleToFill', 'scaleAspectFill', 'redraw'};

  /// Throws [FormatException] when [xml] is not a storyboard with a view.
  static LaunchScreenSpec parse(String xml) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(xml);
    } on XmlException catch (error) {
      throw FormatException('not valid XML (${error.message})');
    }
    final root = document.rootElement;
    if (root.name.local != 'document') {
      throw const FormatException('not an Interface Builder document');
    }
    final view = _rootView(root);
    if (view == null) throw const FormatException('no view to show');

    final approximations = <String>[];
    String? colorName;
    CatalogColor? background = white;
    final backgroundElement = _child(view, 'color', key: 'backgroundColor');
    if (backgroundElement != null) {
      final name = backgroundElement.getAttribute('name');
      if (name != null) {
        colorName = name;
        background = null;
      } else {
        background = _color(backgroundElement, root) ?? white;
      }
    }

    String? image;
    String? backgroundImage;
    final subviews = _child(view, 'subviews');
    for (final element in subviews?.descendantElements ?? <XmlElement>[]) {
      if (element.parentElement?.name.local != 'subviews') continue;
      final kind = element.name.local;
      if (kind == 'imageView') {
        final name = element.getAttribute('image');
        if (name == null || element.getAttribute('hidden') == 'YES') continue;
        final fill = _fillModes.contains(element.getAttribute('contentMode'));
        if (fill && backgroundImage == null) {
          backgroundImage = name;
        } else if (!fill && image == null) {
          image = name;
        } else {
          approximations.add('image "$name"');
        }
      } else if (kind == 'label') {
        final text = element.getAttribute('text');
        approximations.add(text == null ? 'a label' : 'label "$text"');
      } else if (kind != 'view' && kind != 'layoutGuide') {
        approximations.add('a $kind');
      }
    }
    // Only a centred image can be shown; a lone full-screen image is the
    // background (used when it is one colour).
    return LaunchScreenSpec(
      background: background,
      backgroundColorName: colorName,
      imageName: image,
      backgroundImageName: backgroundImage,
      approximations: approximations,
    );
  }

  /// The initial view controller's `view`, or the first `view key="view"`.
  static XmlElement? _rootView(XmlElement root) {
    final initial = root.getAttribute('initialViewController');
    if (initial != null) {
      for (final element in root.descendantElements) {
        if (element.getAttribute('id') == initial) {
          final view = _child(element, 'view', key: 'view');
          if (view != null) return view;
        }
      }
    }
    for (final element in root.descendantElements) {
      if (element.name.local == 'view' &&
          (element.getAttribute('key') == 'view' ||
              element.parentElement?.name.local == 'objects')) {
        return element;
      }
    }
    return null;
  }

  static XmlElement? _child(XmlElement parent, String name, {String? key}) {
    for (final child in parent.childElements) {
      if (child.name.local == name &&
          (key == null || child.getAttribute('key') == key)) {
        return child;
      }
    }
    return null;
  }

  /// An IB `<color>`: explicit RGB or white components, a `systemColor`
  /// (resolved through `<resources>`), or a legacy `cocoaTouchSystemColor`.
  static CatalogColor? _color(XmlElement color, XmlElement root) {
    double? value(String name) {
      final text = color.getAttribute(name);
      return text == null ? null : double.tryParse(text);
    }

    final alpha = value('alpha') ?? 1;
    final space =
        color.getAttribute('customColorSpace') ??
        color.getAttribute('colorSpace');
    final displayP3 = space == 'displayP3';
    final red = value('red');
    final green = value('green');
    final blue = value('blue');
    if (red != null && green != null && blue != null) {
      return CatalogColor(
        red: red,
        green: green,
        blue: blue,
        alpha: alpha,
        displayP3: displayP3,
      );
    }
    final white = value('white');
    if (white != null) {
      return CatalogColor(red: white, green: white, blue: white, alpha: alpha);
    }
    final system =
        color.getAttribute('systemColor') ??
        color.getAttribute('cocoaTouchSystemColor');
    if (system != null) {
      if (systemColors[system] case final known?) return known;
      for (final element in root.descendantElements) {
        if (element.name.local == 'systemColor' &&
            element.getAttribute('name') == system) {
          final definition = _child(element, 'color');
          if (definition != null) return _color(definition, root);
        }
      }
    }
    return null;
  }
}
