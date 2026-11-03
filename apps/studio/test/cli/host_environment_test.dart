// Children get the environment saved in the OS, not the app's start-up
// snapshot: a PATH edited in System settings (or a stale parent) must not
// decide which Flutter and Swift xcross finds.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xcross_studio/src/host/host_platform.dart';

const _machine = r'''

HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Environment
    ComSpec    REG_EXPAND_SZ    %SystemRoot%\system32\cmd.exe
    Path    REG_EXPAND_SZ    %SystemRoot%\system32;D:\flutter-3.47.0\bin
    OS    REG_SZ    Windows_NT
    EMPTY    REG_SZ
    NUMBER    REG_DWORD    0x4

''';

const _user = r'''

HKEY_CURRENT_USER\Environment
    Path    REG_EXPAND_SZ    %LOCALAPPDATA%\Programs\Swift\Toolchains\6.4.2+Asserts\usr\bin\;%SWIFT_RUNTIME%
    SDKROOT    REG_SZ    C:\Swift\Platforms\Windows.platform\Developer\SDKs\Windows.sdk\
    SWIFT_RUNTIME    REG_SZ    C:\Swift\Runtimes\6.4.2\usr\bin
    OS    REG_SZ    UserWins

''';

void main() {
  test('machine then user variables; Path is machine Path + user Path; '
      '%NAME% expanded; inherited spelling kept', () {
    final merged = WindowsHost.mergeSaved(
      machine: _machine,
      user: _user,
      inherited: const {
        'Path': r'D:\flutter-3.47.8\bin;C:\Windows\system32',
        'SystemRoot': r'C:\Windows',
        'LOCALAPPDATA': r'C:\Users\me\AppData\Local',
      },
    );
    expect(merged.containsKey('PATH'), isFalse);
    expect(
      merged['Path'],
      r'C:\Windows\system32;D:\flutter-3.47.0\bin;'
      r'C:\Users\me\AppData\Local\Programs\Swift\Toolchains\6.4.2+Asserts\usr\bin\;'
      r'C:\Swift\Runtimes\6.4.2\usr\bin',
    );
    expect(merged['ComSpec'], r'C:\Windows\system32\cmd.exe');
    expect(
      merged['SDKROOT'],
      r'C:\Swift\Platforms\Windows.platform\Developer\SDKs\Windows.sdk\',
    );
    expect(merged['OS'], 'UserWins');
    expect(merged['EMPTY'], '');
    // Not a string value.
    expect(merged.containsKey('NUMBER'), isFalse);
  });

  test('an unknown %NAME% stays as written; no registry output, no change', () {
    final merged = WindowsHost.mergeSaved(
      machine: '    Path    REG_EXPAND_SZ    %NOPE%\\bin\n',
      user: '',
      inherited: const {},
    );
    expect(merged['Path'], r'%NOPE%\bin');
    expect(
      WindowsHost.mergeSaved(machine: '', user: '', inherited: const {}),
      isEmpty,
    );
  });

  test('Linux children inherit the session environment', () async {
    expect(await const LinuxHost().currentEnvironment(const {}), isEmpty);
  });

  test(
    'on Windows the real saved Path replaces a stale inherited one',
    () async {
      final merged = await const WindowsHost().currentEnvironment(const {
        'Path': r'C:\stale\only',
      });
      expect(merged['Path'], isNotNull);
      expect(merged['Path'], isNot(contains(r'C:\stale\only')));
      expect(merged['Path']!.toLowerCase(), contains('system32'));
    },
    skip: !Platform.isWindows,
  );
}
