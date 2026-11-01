import '../../design_system/design_system.dart';
import '../../src/state/readiness.dart';

XStatus statusOfHealth(Health health) => switch (health) {
  Health.ok => XStatus.ready,
  Health.warning => XStatus.warning,
  Health.failed => XStatus.failed,
  Health.checking => XStatus.running,
  Health.unknown => XStatus.idle,
};

XToolchainState toolchainStateOf(Health health) => switch (health) {
  Health.ok => XToolchainState.valid,
  Health.warning => XToolchainState.mismatched,
  Health.failed => XToolchainState.missing,
  Health.checking => XToolchainState.checking,
  Health.unknown => XToolchainState.unknown,
};

/// Card title of a readiness area.
String areaTitle(ReadinessArea area) => switch (area) {
  ReadinessArea.flutter => 'Flutter',
  ReadinessArea.swift => 'Swift',
  ReadinessArea.llvm => 'LLVM',
  ReadinessArea.darwinSdk => 'Darwin SDK',
  ReadinessArea.auth => 'Authentication',
  ReadinessArea.device => 'Device',
};
