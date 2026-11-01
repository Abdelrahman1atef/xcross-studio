import 'package:path/path.dart' as p;

/// How the GUI starts xcross: an executable plus fixed leading arguments.
class XcrossInvocation {
  const XcrossInvocation(this.executable, [this.prefixArguments = const []]);

  /// An installed or compiled xcross (`xcross` on PATH by default).
  const XcrossInvocation.binary([String path = 'xcross']) : this(path);

  /// A source checkout of XCross Studio: `dart run <repo>/packages/xcross/bin/xcross.dart`.
  XcrossInvocation.fromSource(String repoRoot, {p.Context? context})
    : this('dart', [
        'run',
        (context ?? p.context).join(
          repoRoot,
          'packages',
          'xcross',
          'bin',
          'xcross.dart',
        ),
      ]);

  /// The xcross shipped next to the GUI in a release bundle
  /// (`<app folder>/xcross/bin/xcross[.exe]`), when present.
  static String? bundledNextTo(
    String guiExecutable, {
    required bool windows,
    bool Function(String path)? exists,
  }) {
    final context = windows ? p.windows : p.posix;
    final candidate = context.join(
      context.dirname(guiExecutable),
      'xcross',
      'bin',
      windows ? 'xcross.exe' : 'xcross',
    );
    return (exists ?? (_) => false)(candidate) ? candidate : null;
  }

  /// True for the default `xcross`-on-PATH choice.
  bool get isDefault => executable == 'xcross' && prefixArguments.isEmpty;

  final String executable;
  final List<String> prefixArguments;

  List<String> argumentsFor(List<String> command) => [
    ...prefixArguments,
    ...command,
  ];

  Map<String, Object> toJson() => {
    'executable': executable,
    'prefixArguments': prefixArguments,
  };

  static XcrossInvocation fromJson(Object? json) {
    if (json
        case {
          'executable': final String executable,
          'prefixArguments': final List<Object?> prefix,
        }
        when executable.isNotEmpty) {
      return XcrossInvocation(executable, [for (final a in prefix) '$a']);
    }
    return const XcrossInvocation.binary();
  }

  @override
  String toString() => [executable, ...prefixArguments].join(' ');
}

/// Build mode of a Flutter app.
enum BuildMode { debug, profile, release }

/// `xcross logs --preset`.
enum LogPreset { push, crash, flutter }

/// Minimum log level for `xcross logs --level`.
enum LogLevel { debug, info, notice, error, fault }

/// The xcross command lines the GUI runs. The GUI holds no build or device
/// logic: every action is one of these commands.
abstract final class XcrossCommands {
  static List<String> doctor() => const ['doctor'];

  static List<String> flutterDoctor() => const ['flutter', 'doctor'];

  static List<String> build({
    required BuildMode mode,
    bool ipa = true,
    String? buildName,
    String? buildNumber,
  }) => [
    'flutter',
    'build',
    '--${mode.name}',
    if (ipa) '--ipa',
    if (_set(buildName)) ...['--build-name', buildName!.trim()],
    if (_set(buildNumber)) ...['--build-number', buildNumber!.trim()],
  ];

  static List<String> run({required BuildMode mode, String? udid}) => [
    'flutter',
    'run',
    '--${mode.name}',
    if (_set(udid)) ...['--udid', udid!],
  ];

  static List<String> install(
    String path, {
    String? udid,
    String? ddi,
    bool launch = true,
  }) => [
    'install',
    path,
    if (_set(udid)) ...['--udid', udid!],
    if (_set(ddi)) ...['--ddi', ddi!],
    if (!launch) '--no-launch',
  ];

  /// `xcross sign` (feature 011): a signed .ipa next to the input, nothing
  /// installed. [udid] is registered and included in the profile.
  static List<String> sign(String path, {String? output, String? udid}) => [
    'sign',
    path,
    if (_set(output)) ...['-o', output!],
    if (_set(udid)) ...['--udid', udid!],
  ];

  static List<String> devices() => const ['devices', '--json'];

  static List<String> appList({String? udid}) => [
    'app',
    'list',
    '--json',
    if (_set(udid)) ...['--udid', udid!],
  ];

  static List<String> appInfo(String bundleId, {String? udid}) => [
    'app',
    'info',
    bundleId,
    '--json',
    if (_set(udid)) ...['--udid', udid!],
  ];

  static List<String> logs({
    String? app,
    LogPreset? preset,
    List<String> processes = const [],
    String? grep,
    LogLevel? level,
    String? udid,
  }) => [
    'logs',
    '--json',
    if (_set(app)) ...['--app', app!.trim()],
    if (preset != null) ...['--preset', preset.name],
    for (final process in processes)
      if (_set(process)) ...['--process', process.trim()],
    if (_set(grep)) ...['--grep', grep!],
    if (level != null) ...['--level', level.name],
    if (_set(udid)) ...['--udid', udid!],
  ];

  static List<String> crashesList({String? app, String? udid}) => [
    'crashes',
    'list',
    '--json',
    if (_set(app)) ...['--app', app!.trim()],
    if (_set(udid)) ...['--udid', udid!],
  ];

  static List<String> crashesPull(
    String name, {
    required String outDirectory,
    String? udid,
  }) => [
    'crashes',
    'pull',
    name,
    '--out',
    outDirectory,
    if (_set(udid)) ...['--udid', udid!],
  ];

  static List<String> authAppleId(String appleId, {String? password}) => [
    'auth',
    '--apple-id=${appleId.trim()}',
    if (_set(password)) ...['--password', password!],
  ];

  static List<String> authApiKey({
    required String issuerId,
    required String keyId,
    required String privateKeyPath,
  }) => [
    'auth',
    '--issuer-id',
    issuerId.trim(),
    '--key-id',
    keyId.trim(),
    '--private-key',
    privateKeyPath,
  ];

  static List<String> authClean() => const ['auth', 'clean'];

  /// [command] for display: secrets (`--password`) replaced by `••••`.
  static String display(List<String> command) {
    final shown = <String>[];
    for (var i = 0; i < command.length; i++) {
      shown.add(command[i]);
      if (command[i] == '--password' && i + 1 < command.length) {
        shown.add('••••');
        i++;
      }
    }
    return [
      'xcross',
      for (final part in shown) part.contains(' ') ? '"$part"' : part,
    ].join(' ');
  }

  static bool _set(String? value) => value != null && value.trim().isNotEmpty;
}
