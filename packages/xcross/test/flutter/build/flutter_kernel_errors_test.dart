import 'package:meta/meta.dart';
import 'package:test/test.dart';
import 'package:xcross/src/shared/flutter/flutter_kernel_compiler.dart';

/// What `runChecked` throws when frontend_server exits 254: the command, then
/// the compiler's output.
@internal
const failure =
    r'command failed (254): C:\flutter\bin\cache\dart-sdk\bin\dartaotruntime.exe '
    r'C:\flutter\bin\cache\dart-sdk\bin\snapshots\frontend_server_aot.dart.snapshot '
    r'--sdk-root C:\flutter\bin\cache\artifacts\engine\common\flutter_patched_sdk/ '
    '--target=flutter package:app/main.dart\n'
    "lib/main.dart:12:3: Error: Expected ';' after this.\n"
    '  foo()\n'
    '  ^\n'
    "lib/screens/home.dart:40:10: Error: The getter 'titel' isn't defined "
    "for the type 'Widget'.\n"
    " - 'Widget' is from 'package:flutter/src/widgets/framework.dart'.\n"
    'Try correcting the name to the name of an existing getter.\n'
    '    return titel;\n'
    '           ^^^^^\n'
    'lib/old.dart:1:8: Warning: Import of unused library.\n'
    "C:/Users/dev/app/lib/util.dart:3:1: Error: Type 'Foo' not found.\n"
    "lib/main.dart:12:3: Error: Expected ';' after this.\n";

void main() {
  test('finds the compile errors frontend_server printed', () {
    expect(FlutterKernelCompiler.compileErrors(failure), [
      "lib/main.dart:12:3: Error: Expected ';' after this.",
      "lib/screens/home.dart:40:10: Error: The getter 'titel' isn't defined for the type 'Widget'.",
      "C:/Users/dev/app/lib/util.dart:3:1: Error: Type 'Foo' not found.",
    ]);
  });

  test('puts the Dart errors ahead of the command line', () {
    final message = FlutterKernelCompiler.compileFailure(failure)!;
    final lines = message.split('\n');
    expect(lines.first, "lib/main.dart:12:3: Error: Expected ';' after this.");
    expect(lines[2], startsWith('C:/Users/dev/app/lib/util.dart:3:1: Error:'));
    expect(lines[3], isEmpty);
    expect(lines[4], startsWith('command failed (254): '));
    expect(message, endsWith(failure));
  });

  test('shows the first few and counts the rest', () {
    final many = [
      'command failed (254): dart frontend_server',
      for (var i = 1; i <= 8; i++) 'lib/a.dart:$i:1: Error: Problem $i.',
    ].join('\n');
    final lines = FlutterKernelCompiler.compileFailure(many)!.split('\n');
    expect(lines.take(5), [
      for (var i = 1; i <= 5; i++) 'lib/a.dart:$i:1: Error: Problem $i.',
    ]);
    expect(lines[5], '… and 3 more Dart compile errors.');
  });

  test('leaves a failure without compile errors alone', () {
    expect(
      FlutterKernelCompiler.compileFailure(
        'command failed (255): dart frontend_server\nUnhandled exception: boom',
      ),
      isNull,
    );
  });
}
