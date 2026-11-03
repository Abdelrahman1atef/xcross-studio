// studio: 018 — the toolchain identity App Store Connect reads from every
// bundle's Info.plist (specs/018-app-store-build, AC-018-6).
import 'dart:convert';
import 'dart:typed_data';

import 'package:cli_kit/shared/platform/platform_host.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:propertylistserialization/propertylistserialization.dart';
import 'package:xcross/src/shared/artifact/plist_xml.dart';
import 'package:xml/xml.dart';

/// Xcode and SDK build numbers of the installed Darwin SDK.
@internal
@immutable
final class XcodeBuildInfo {
  const XcodeBuildInfo({
    this.xcodeVersion,
    this.xcodeBuild,
    this.sdkVersion,
    this.sdkBuild,
  });

  /// Reads `<iosSdk>/System/Library/CoreServices/SystemVersion.plist` and the
  /// record at [bundleRoot]. Missing or unreadable files leave fields null.
  factory XcodeBuildInfo.read({
    required HostFileSystemInterface fileSystem,
    required p.Context paths,
    required String iosSdk,
    String? bundleRoot,
  }) {
    final system = _plist(
      fileSystem,
      paths.join(
        iosSdk,
        'System',
        'Library',
        'CoreServices',
        'SystemVersion.plist',
      ),
    );
    final xcode = bundleRoot == null
        ? const <Object?, Object?>{}
        : _plist(fileSystem, paths.join(bundleRoot, recordFileName));
    String? text(Map<Object?, Object?> map, String key) =>
        map[key] is String && (map[key]! as String).isNotEmpty
        ? map[key]! as String
        : null;
    return XcodeBuildInfo(
      xcodeVersion: text(xcode, 'CFBundleShortVersionString'),
      xcodeBuild: text(xcode, 'ProductBuildVersion'),
      sdkVersion: text(system, 'ProductVersion'),
      sdkBuild: text(system, 'ProductBuildVersion'),
    );
  }

  /// Written by `xcross sdk install`: the `.xip`'s
  /// `Xcode.app/Contents/version.plist`, at the artifact bundle root.
  static const recordFileName = 'xcross-xcode-version.plist';

  /// The compiler Xcode records.
  static const compiler = 'com.apple.compilers.llvm.clang.1_0';

  /// Xcode's `CFBundleShortVersionString`, such as `26.1`.
  final String? xcodeVersion;

  /// Xcode's `ProductBuildVersion`, such as `17B55`.
  final String? xcodeBuild;

  /// The iOS SDK's `ProductVersion`, such as `26.1`.
  final String? sdkVersion;

  /// The iOS SDK's `ProductBuildVersion`.
  final String? sdkBuild;

  /// `DTXcode`: the Xcode version as `MMmp` (26.1 → `2610`, 26.1.1 →
  /// `2611`); without a recorded Xcode, derived from the SDK version (an
  /// SDK ships with the Xcode of the same number).
  String? get dtXcode {
    final version = xcodeVersion ?? sdkVersion;
    if (version == null) return null;
    return dtXcodeOf(version);
  }

  /// [version] (`major.minor[.patch]`) as Xcode's `DTXcode`.
  @visibleForTesting
  static String? dtXcodeOf(String version) {
    final parts = version.split('.').map(int.tryParse).toList();
    if (parts.isEmpty || parts.first == null) return null;
    final major = parts.first!;
    final minor = parts.length > 1 ? (parts[1] ?? 0) : 0;
    final patch = parts.length > 2 ? (parts[2] ?? 0) : 0;
    if (minor > 9 || patch > 9) return null;
    return '${major.toString().padLeft(2, '0')}$minor$patch';
  }

  /// The keys to write; keys with unknown values are left out.
  Map<String, String> get keys => {
    'DTXcode': ?dtXcode,
    'DTXcodeBuild': ?xcodeBuild,
    'DTSDKBuild': ?sdkBuild,
    'DTPlatformBuild': ?sdkBuild,
    'DTCompiler': compiler,
  };

  /// [xml] (an XML plist) with [keys] set, replacing existing values.
  String applyTo(String xml) {
    final values = keys;
    if (values.isEmpty) return xml;
    final document = XmlDocument.parse(xml);
    final root = document.rootElement.getElement('dict');
    if (root == null) return xml;
    for (final MapEntry(:key, :value) in values.entries) {
      final element = PlistXml.element('string', value);
      final current = PlistXml.valueFor(root, key);
      if (current == null) {
        root.children
          ..add(PlistXml.element('key', key))
          ..add(element);
      } else {
        root.children[root.children.indexOf(current)] = element;
      }
    }
    return document.toXmlString();
  }

  static Map<Object?, Object?> _plist(
    HostFileSystemInterface fileSystem,
    String path,
  ) {
    final file = fileSystem.file(path);
    if (!file.existsSync()) return const {};
    // The parser prints a stack trace for every input it rejects, so the
    // format is chosen from the header instead of by trying both.
    try {
      final bytes = file.readAsBytesSync();
      final value = _isBinary(bytes)
          ? PropertyListSerialization.propertyListWithData(
              ByteData.sublistView(bytes),
            )
          : PropertyListSerialization.propertyListWithString(
              utf8.decode(bytes, allowMalformed: true),
            );
      return value is Map ? value : const {};
    } on Object {
      return const {};
    }
  }

  static bool _isBinary(Uint8List bytes) =>
      bytes.length >= 8 &&
      ascii.decode(bytes.sublist(0, 8), allowInvalid: true) == 'bplist00';
}
