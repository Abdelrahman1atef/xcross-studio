// studio: 018 — the minimum iOS a binary's code needs, for the build and the
// release check to compare with the bundle's MinimumOSVersion (App Store
// Connect 90208: "does not support the minimum OS Version specified in the
// Info.plist").
import 'dart:typed_data';

import 'package:studio_ext/src/shared/release/macho_build_version.dart';

/// The minimum OS the arm64 code of [bytes] (a thin or fat Mach-O) was linked
/// for, as `major.minor[.patch]`; null when it has no build version.
String? machOMinimumOS(Uint8List bytes) =>
    MachOBuildVersion.read(bytes)?.minimumOS;

/// Compares two dotted versions number by number (`15.0` > `13.0`, `14` ==
/// `14.0`). A part that is not a number counts as 0.
int compareOsVersions(String a, String b) {
  List<int> parts(String version) => [
    for (final part in version.trim().split('.')) int.tryParse(part) ?? 0,
  ];
  final left = parts(a);
  final right = parts(b);
  for (var i = 0; i < left.length || i < right.length; i++) {
    final x = i < left.length ? left[i] : 0;
    final y = i < right.length ? right[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}
