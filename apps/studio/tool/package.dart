// Builds a portable XCross Studio folder and archive for this host:
//
//   dist/xcross-studio-<os>-x64/
//     xcross_studio(.exe) + Flutter runtime files      (the GUI)
//     xcross/bin/xcross(.exe), xcross/lib/...          (the CLI bundle)
//     LICENSE, NOTICE.txt
//
// The GUI finds xcross/bin/xcross next to itself (see
// XcrossInvocation.bundledNextTo). Run from apps/studio:
//
//   dart run tool/package.dart [--skip-cli] [--skip-gui]
import 'dart:io';

import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final studio = Directory.current.path;
  final repo = p.normalize(p.join(studio, '..', '..'));
  if (!File(p.join(repo, 'packages', 'xcross', 'bin', 'xcross.dart'))
      .existsSync()) {
    stderr.writeln('Run this from apps/studio inside the repository.');
    exit(64);
  }
  final windows = Platform.isWindows;
  final os = windows ? 'windows' : 'linux';

  if (!args.contains('--skip-cli')) {
    await _run('dart', [
      'run',
      'tool/build_xcross.dart',
    ], p.join(repo, 'packages', 'xcross'));
  }
  if (!args.contains('--skip-gui')) {
    await _run('flutter', ['build', os, '--release'], studio);
  }

  final gui = windows
      ? p.join(studio, 'build', 'windows', 'x64', 'runner', 'Release')
      : p.join(studio, 'build', 'linux', 'x64', 'release', 'bundle');
  final cli = p.join(
    repo,
    'packages',
    'xcross',
    'build',
    'cli',
    '${os}_x64',
    'bundle',
  );
  for (final dir in [gui, cli]) {
    if (!Directory(dir).existsSync()) {
      stderr.writeln('Missing build output: $dir');
      exit(1);
    }
  }

  final name = 'xcross-studio-$os-x64';
  final dist = p.join(repo, 'dist');
  final out = p.join(dist, name);
  if (Directory(out).existsSync()) Directory(out).deleteSync(recursive: true);
  _copy(gui, out);
  _copy(cli, p.join(out, 'xcross'));
  File(p.join(repo, 'LICENSE')).copySync(p.join(out, 'LICENSE'));
  File(p.join(out, 'NOTICE.txt')).writeAsStringSync(
    'XCross Studio is free software under the GNU AGPL-3.0 (see LICENSE); '
    'source: https://github.com/Abdelrahman1atef/xcross-studio\n'
    'It is a fork of xcross (https://github.com/arxdeus/xcross).\n'
    'Not affiliated with or endorsed by Apple Inc. No Apple software is '
    'included: you provide your own Xcode/SDK and developer disk images.\n'
    'pymobiledevice3 (GPL-3.0) is installed separately and run as a '
    'subprocess.\n',
  );

  final archive = windows ? '$name.zip' : '$name.tar.gz';
  final archivePath = p.join(dist, archive);
  if (File(archivePath).existsSync()) File(archivePath).deleteSync();
  // bsdtar (Windows 10+) writes zip with -a; GNU tar writes .tar.gz.
  await _run(
    'tar',
    windows ? ['-a', '-c', '-f', archive, name] : ['-czf', archive, name],
    dist,
  );
  stdout.writeln('Packaged: $out');
  stdout.writeln('Archive:  $archivePath');

  if (!windows) {
    final version = Platform.environment['XCROSS_STUDIO_VERSION'] ?? '0.1.0';
    await _debian(studio, dist, out, version);
    final appimagetool = Platform.environment['APPIMAGETOOL'];
    if (appimagetool == null || appimagetool.isEmpty) {
      stdout.writeln('AppImage: skipped (set APPIMAGETOOL to appimagetool).');
    } else {
      await _appImage(studio, dist, out, appimagetool);
    }
  }
}

const _appId = 'dev.xcrossstudio.xcross_studio';

/// `dist/xcross-studio_<version>_amd64.deb`: the folder under
/// /opt/xcross-studio, a launcher in /usr/bin, the desktop entry and icon.
Future<void> _debian(
  String studio,
  String dist,
  String folder,
  String version,
) async {
  final root = p.join(dist, 'deb-root');
  if (Directory(root).existsSync()) Directory(root).deleteSync(recursive: true);
  _copy(folder, p.join(root, 'opt', 'xcross-studio'));
  final bin = Directory(p.join(root, 'usr', 'bin'))
    ..createSync(recursive: true);
  Link(p.join(bin.path, 'xcross-studio'))
      .createSync('/opt/xcross-studio/xcross_studio');
  final packaging = p.join(studio, 'linux', 'packaging');
  final applications = Directory(p.join(root, 'usr', 'share', 'applications'))
    ..createSync(recursive: true);
  File(p.join(packaging, '$_appId.desktop'))
      .copySync(p.join(applications.path, '$_appId.desktop'));
  final icons = Directory(
    p.join(root, 'usr', 'share', 'icons', 'hicolor', '256x256', 'apps'),
  )..createSync(recursive: true);
  File(p.join(packaging, 'xcross-studio.png'))
      .copySync(p.join(icons.path, '$_appId.png'));
  final control = Directory(p.join(root, 'DEBIAN'))..createSync();
  File(p.join(control.path, 'control')).writeAsStringSync(
    'Package: xcross-studio\n'
    'Version: $version\n'
    'Section: devel\n'
    'Priority: optional\n'
    'Architecture: amd64\n'
    'Maintainer: XCross Studio contributors '
    '<xcross-studio@users.noreply.github.com>\n'
    'Depends: libgtk-3-0 | libgtk-3-0t64, usbmuxd\n'
    'Recommends: pipx\n'
    'Homepage: https://github.com/Abdelrahman1atef/xcross-studio\n'
    'Description: Build, sign, install and debug Flutter iOS apps without a '
    'Mac\n'
    ' Desktop app plus the xcross command-line tool '
    '(/opt/xcross-studio/xcross/bin/xcross).\n'
    ' Not affiliated with Apple. Install pymobiledevice3 separately '
    '(pipx install pymobiledevice3).\n',
  );
  final deb = 'xcross-studio_${version}_amd64.deb';
  await _run('dpkg-deb', [
    '--build',
    '--root-owner-group',
    'deb-root',
    deb,
  ], dist);
  Directory(root).deleteSync(recursive: true);
  stdout.writeln('Debian:   ${p.join(dist, deb)}');
}

/// `dist/xcross-studio-x86_64.AppImage` built with [appimagetool].
Future<void> _appImage(
  String studio,
  String dist,
  String folder,
  String appimagetool,
) async {
  final appDir = p.join(dist, 'XCrossStudio.AppDir');
  if (Directory(appDir).existsSync()) {
    Directory(appDir).deleteSync(recursive: true);
  }
  _copy(folder, appDir);
  final packaging = p.join(studio, 'linux', 'packaging');
  File(p.join(packaging, '$_appId.desktop'))
      .copySync(p.join(appDir, '$_appId.desktop'));
  File(p.join(packaging, 'xcross-studio.png'))
      .copySync(p.join(appDir, '$_appId.png'));
  final appRun = File(p.join(appDir, 'AppRun'))
    ..writeAsStringSync(
      '#!/bin/sh\n'
      'HERE="\$(dirname "\$(readlink -f "\$0")")"\n'
      'exec "\$HERE/xcross_studio" "\$@"\n',
    );
  await _run('chmod', ['+x', appRun.path], dist);
  await _run(
    appimagetool,
    ['--no-appstream', appDir, 'xcross-studio-x86_64.AppImage'],
    dist,
    environment: const {'ARCH': 'x86_64', 'APPIMAGE_EXTRACT_AND_RUN': '1'},
  );
  Directory(appDir).deleteSync(recursive: true);
  stdout.writeln('AppImage: ${p.join(dist, 'xcross-studio-x86_64.AppImage')}');
}

Future<void> _run(
  String executable,
  List<String> args,
  String cwd, {
  Map<String, String>? environment,
}) async {
  stdout.writeln('\$ $executable ${args.join(' ')}   (in $cwd)');
  final process = await Process.start(
    executable,
    args,
    workingDirectory: cwd,
    environment: environment,
    runInShell: Platform.isWindows,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  if (code != 0) {
    stderr.writeln('$executable failed with exit code $code');
    exit(code);
  }
}

void _copy(String from, String to) {
  Directory(to).createSync(recursive: true);
  for (final entity in Directory(from).listSync(recursive: true)) {
    final target = p.join(to, p.relative(entity.path, from: from));
    if (entity is Directory) {
      Directory(target).createSync(recursive: true);
    } else if (entity is File) {
      Directory(p.dirname(target)).createSync(recursive: true);
      entity.copySync(target);
    }
  }
}
