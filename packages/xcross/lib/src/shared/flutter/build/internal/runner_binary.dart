import 'package:meta/meta.dart';

/// Result of building the ObjC Runner shim: the xcframework used and the
/// linked Runner binary path.
@internal
@immutable
final class RunnerBinary {
  const RunnerBinary({
    required this.xcframework,
    required this.runnerBinary,
    required this.sdkName,
    this.sceneDelegateClass, // studio: 007
  });

  final String xcframework;
  final String runnerBinary;
  final String sdkName;

  // studio: 007 — set when the Runner was built from the project's sources:
  // the `UISceneDelegateClassName` its Info.plist must name. Null keeps the
  // shim's `SceneDelegate`.
  final String? sceneDelegateClass;
}
