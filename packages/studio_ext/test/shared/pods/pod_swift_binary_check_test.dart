import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:studio_ext/src/shared/pods/pod_swift_binary_check.dart';
import 'package:test/test.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('swift-binary-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });

  test('AC-046-12 requires an interface for each selected Swift slice', () {
    const check = PodSwiftBinaryCheck(
      directoryFactory: Directory.new,
      fileFactory: File.new,
    );
    final framework = Directory(path.join(root.path, 'SDK.framework'));
    final module = Directory(
      path.join(framework.path, 'Modules', 'SDK.swiftmodule'),
    );
    module.createSync(recursive: true);
    File(
      path.join(module.path, 'arm64-apple-ios.swiftinterface'),
    ).writeAsStringSync('// swift interface');
    check.requireInterface(framework, simulator: false);
    expect(
      () => check.requireInterface(framework, simulator: true),
      throwsA(isA<PodSwiftBinaryIncompatible>()),
    );
    File(
      path.join(module.path, 'arm64-apple-ios-simulator.swiftinterface'),
    ).writeAsStringSync('// swift interface');
    check.requireInterface(framework, simulator: true);
  });

  test('AC-046-12 ObjC binary needs no Swift interface', () {
    const check = PodSwiftBinaryCheck(
      directoryFactory: Directory.new,
      fileFactory: File.new,
    );
    final framework = Directory(path.join(root.path, 'ObjC.framework'));
    framework.createSync(recursive: true);
    check.requireInterface(framework, simulator: false);
  });
}
