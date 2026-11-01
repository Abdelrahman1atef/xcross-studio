// studio: 003 — pass the Flutter app's declared entitlements to the signer.
import 'package:apple_developer_kit/shared/appstoreconnect/asc_capabilities.dart';
import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:propertylistserialization/propertylistserialization.dart';
import 'package:xcross/src/shared/artifact/app_capabilities.dart';
import 'package:xcross/src/shared/artifact/app_entitlements.dart';

/// The app target's `.entitlements`, handed to the signer the same way the
/// Compose builder does: `XCrossEntitlements` (what the app declares) and
/// `XCrossCapabilities` (what App Store Connect must enable before the
/// profile is issued). The signer removes both keys before signing.
@internal
final class FlutterAppEntitlements {
  FlutterAppEntitlements(this.fileSystem, this.paths);

  final HostFileSystemInterface fileSystem;
  final p.Context paths;

  /// The entitlements file: the app target's `CODE_SIGN_ENTITLEMENTS`
  /// ([fromProject]), else `ios/Runner/Runner.entitlements`.
  String? locate(String projectRoot, {String? fromProject}) {
    if (fromProject != null && fileSystem.file(fromProject).existsSync()) {
      return fromProject;
    }
    final fallback = paths.join(
      projectRoot,
      'ios',
      'Runner',
      'Runner.entitlements',
    );
    return fileSystem.file(fallback).existsSync() ? fallback : null;
  }

  /// The declared entitlements at [path], or throws [FormatException] when
  /// the file is not a dictionary plist.
  Map<String, Object> read(String path) {
    return _dictionary(fileSystem.file(path).readAsStringSync());
  }

  /// [plistXml] with the signer keys for [declared] added (unchanged when
  /// [declared] is empty). Throws [FormatException] when [plistXml] is not a
  /// dictionary plist.
  static String withSigningKeys(String plistXml, Map<String, Object> declared) {
    if (declared.isEmpty) return plistXml;
    final capabilities = AscCapabilities.forEntitlements(declared);
    final updated = <String, Object>{
      ..._dictionary(plistXml),
      AppEntitlements.infoPlistKey: declared,
      if (capabilities.isNotEmpty) AppCapabilities.infoPlistKey: capabilities,
    };
    return PropertyListSerialization.stringWithPropertyList(updated);
  }

  static const _doctype =
      '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
      '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">';

  /// The top-level dictionary of the XML plist [xml]. The parser insists on
  /// the DOCTYPE line, which hand-written files often omit, so it is added
  /// when missing.
  static Map<String, Object> _dictionary(String xml) {
    var source = xml;
    if (!source.contains('<!DOCTYPE')) {
      final start = source.indexOf('<plist');
      if (start >= 0) {
        source = [
          source.substring(0, start),
          _doctype,
          source.substring(start),
        ].join('\n');
      }
    }
    final Object root;
    try {
      root = PropertyListSerialization.propertyListWithString(source);
      // The parser reports malformed input with assorted error types.
    } on Object catch (error) {
      throw FormatException('not a valid property list ($error)');
    }
    if (root is! Map) throw const FormatException('not a dictionary');
    return {
      for (final MapEntry(:key, :value) in root.entries)
        if (value != null) '$key': value as Object,
    };
  }
}
