import 'package:meta/meta.dart';

@internal
enum DoctorStatus { success, warning, failure }

@internal
final class DoctorCheck {
  const DoctorCheck(this.status, this.name, this.message, {this.path});

  const DoctorCheck.success(this.name, this.message, {this.path})
    : status = DoctorStatus.success;
  const DoctorCheck.warning(this.name, this.message, {this.path})
    : status = DoctorStatus.warning;
  const DoctorCheck.failure(this.name, this.message, {this.path})
    : status = DoctorStatus.failure;

  final DoctorStatus status;
  final String name;
  final String message;
  final String? path;

  // studio: 015 — [path] without the Windows long-path prefix, for output
  // ("✓ Flutter SDK  \\?\D:\flutter", seen on Windows 2026-11-02).
  String? get shownPath {
    final value = path;
    const unc = r'\\?\UNC\';
    const local = r'\\?\';
    if (value == null) return null;
    if (value.startsWith(unc)) return '\\\\${value.substring(unc.length)}';
    if (value.startsWith(local)) return value.substring(local.length);
    return value;
  }
}

@internal
typedef DoctorExamine = Future<List<DoctorCheck>> Function();

/// A titled group of related checks, examined together and reported under
/// one status header the way `flutter doctor` groups its categories.
@internal
final class DoctorSection {
  const DoctorSection(this.title, this.examine);

  final String title;
  final DoctorExamine examine;
}

@internal
extension DoctorStatusWorst on Iterable<DoctorCheck> {
  /// The most severe status among these checks; an empty group is healthy.
  DoctorStatus get worst => fold(
    DoctorStatus.success,
    (worst, check) => check.status.index > worst.index ? check.status : worst,
  );
}
