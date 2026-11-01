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
}

Future<void> _run(String executable, List<String> args, String cwd) async {
  stdout.writeln('\$ $executable ${args.join(' ')}   (in $cwd)');
  final process = await Process.start(
    executable,
    args,
    workingDirectory: cwd,
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
