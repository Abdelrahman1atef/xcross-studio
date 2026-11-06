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

  /// Whether [executable] is the CLI inside an XCross Studio bundle
  /// (`<app folder>/xcross/bin/xcross[.exe]` next to `xcross_studio[.exe]`).
  /// Older versions saved that absolute path as the user's choice, which
  /// pinned every later copy of the app to one folder's CLI.
  static bool isStudioBundled(
    String executable, {
    required bool windows,
    required bool Function(String path) exists,
  }) {
    final context = windows ? p.windows : p.posix;
    final bin = context.dirname(executable);
    final cli = context.dirname(bin);
    if (context.basename(executable).toLowerCase() !=
            (windows ? 'xcross.exe' : 'xcross') ||
        context.basename(bin) != 'bin' ||
        context.basename(cli) != 'xcross') {
      return false;
    }
    return exists(
      context.join(
        context.dirname(cli),
        windows ? 'xcross_studio.exe' : 'xcross_studio',
      ),
    );
  }

  /// True for the default choice: the CLI bundled with the app, else
  /// `xcross` on PATH.
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
  /// The host and project check. xcross has no top-level `doctor`;
  /// `flutter doctor` checks the toolchain, SDK, device service and sign-in
  /// (and the project when run inside one).
  static List<String> doctor() => const ['flutter', 'doctor'];

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

  // Feature 022: the release steps (features 018–021).

  /// `xcross release gate --json`.
  static List<String> releaseGate() => const ['release', 'gate', '--json'];

  /// The App Store build: signed, archived, optionally with the next build
  /// number from App Store Connect.
  static List<String> appStoreBuild({bool autoBuildNumber = false}) => [
    'flutter',
    'build',
    '--release',
    '--ipa',
    '--export-method',
    'app-store',
    if (autoBuildNumber) ...['--build-number', 'auto'],
  ];

  /// `xcross icons check --json` (feature 023).
  static List<String> iconsCheck() => const ['icons', 'check', '--json'];

  /// `xcross icons preview --serve`: draws each design sent to it (feature
  /// 024), writing images into [folder].
  static List<String> iconsPreviewServe(String folder) => [
    'icons',
    'preview',
    '--serve',
    '--output',
    folder,
  ];

  /// `xcross icons generate` with a design's [options] and [flags]; [output]
  /// or [zip] leave the project alone (feature 024).
  static List<String> iconsDesign(
    String image,
    Map<String, String> options, {
    List<String> flags = const [],
    String? output,
    String? zip,
    bool save = false,
  }) => [
    'icons',
    'generate',
    image,
    for (final MapEntry(:key, :value) in options.entries) ...['--$key', value],
    for (final flag in flags) '--$flag',
    if (output != null) ...['--output', output],
    if (zip != null) ...['--zip', zip],
    if (save) '--save-config',
    '--json',
  ];

  /// `xcross splash check` as JSON (feature 024).
  static List<String> splashCheck() => const ['splash', 'check', '--json'];

  /// `xcross splash generate` with a design's [options] (feature 024).
  static List<String> splashGenerate(
    String logo,
    Map<String, String> options, {
    String? output,
    String? zip,
    bool save = false,
  }) => [
    'splash',
    'generate',
    logo,
    for (final MapEntry(:key, :value) in options.entries) ...['--$key', value],
    if (output != null) ...['--output', output],
    if (zip != null) ...['--zip', zip],
    if (save) '--save-config',
    '--json',
  ];

  /// `xcross icons generate` with the image, background (`auto` or
  /// `#RRGGBB`) and margin in percent, as JSON (feature 023).
  static List<String> iconsGenerate(
    String image, {
    String background = 'auto',
    int padding = 0,
  }) => [
    'icons',
    'generate',
    image,
    '--background',
    background,
    '--padding',
    '$padding',
    '--json',
  ];

  /// `xcross project version --json`, setting [version] and [build] or
  /// raising [bump] (`major`, `minor`, `patch`, `build`) when given.
  static List<String> projectVersion({
    String? version,
    String? build,
    String? bump,
  }) => [
    'project',
    'version',
    if (version != null) version.trim(),
    if (build != null) ...['--build', build.trim()],
    if (bump != null) ...['--bump', bump],
    '--json',
  ];

  /// `xcross release check --json`.
  static List<String> releaseCheck() => const [
    'release',
    'check',
    '--online',
    '--json',
  ];

  /// `xcross publish --wait --json`.
  static List<String> publish() => const ['publish', '--wait', '--json'];

  /// `xcross testflight status --json`.
  static List<String> testflightStatus() => const [
    'testflight',
    'status',
    '--json',
  ];

  /// `xcross testflight add --group <name>`.
  static List<String> testflightAdd(String group) => [
    'testflight',
    'add',
    '--group',
    group.trim(),
  ];

  /// `xcross testflight what-to-test "<text>"`.
  static List<String> whatToTest(String text) => [
    'testflight',
    'what-to-test',
    text.trim(),
  ];

  /// `xcross appstore status --json`.
  static List<String> appStoreStatus() => const [
    'appstore',
    'status',
    '--json',
  ];

  /// `xcross appstore submit [--dry-run]`.
  static List<String> appStoreSubmit({required bool dryRun}) => [
    'appstore',
    'submit',
    if (dryRun) '--dry-run',
  ];

  /// `xcross release ci`.
  static List<String> releaseCi() => const ['release', 'ci'];

  /// `xcross devices --watch --json` (feature 017): a snapshot at start and
  /// after every plug, unplug or device service change.
  static List<String> devicesWatch() => const ['devices', '--watch', '--json'];

  /// `xcross project bundle-id [original|prefixed] --json` (feature 016):
  /// read, or save, the App ID the open project is signed under.
  static List<String> projectBundleId({bool? realAppId}) => [
    'project',
    'bundle-id',
    if (realAppId != null) realAppId ? 'original' : 'prefixed',
    '--json',
  ];

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

  static List<String> authAppleId(
    String appleId, {
    String? password,
    String? anisetteUrl,
  }) => [
    'auth',
    '--apple-id=${appleId.trim()}',
    if (_set(password)) ...['--password', password!],
    if (_set(anisetteUrl)) '--anisette-url=${anisetteUrl!.trim()}',
  ];

  /// Omnisette server `xcross auth` uses for Apple ID sign-in when neither
  /// `--anisette-url` nor `XCROSS_ANISETTE_URL` is set (from its `--help`).
  static const defaultAnisetteUrl = 'https://mac-ani.jkcoxson.com';

  // studio: 013 — commands behind the setup wizard, Settings and Devices.

  /// `xcross setup`: runs the setup script for the host's package manager
  /// (winget, Scoop, Chocolatey or direct downloads). [yes] accepts every
  /// installer without prompting (the GUI asks first).
  static List<String> setup({bool yes = false}) => ['setup', if (yes) '--yes'];

  /// `xcross sdk install <Xcode.xip>`: builds the Darwin SDK once.
  static List<String> sdkInstall(String xip) => ['sdk', 'install', xip];

  static List<String> version() => const ['--version'];

  // Feature 014: a Flutter SDK with an iOS compiler for this computer.
  static List<String> flutterSdkList() => const [
    'flutter',
    'sdk',
    'list',
    '--json',
  ];

  static List<String> flutterSdkAuto() => const [
    'flutter',
    'sdk',
    'auto',
    '--yes',
  ];

  static List<String> flutterSdkReset() => const ['flutter', 'sdk', 'reset'];

  /// `xcross update --check`: reports the target version, installs nothing.
  static List<String> updateCheck() => const ['update', '--check'];

  /// `xcross ide vscode` / `xcross ide idea` (run in the project folder).
  static List<String> ide(String editor) => ['ide', editor];

  /// `xcross tunnel`: iOS 17+ developer tunnel (needs an Administrator
  /// terminal on Windows or sudo on Linux).
  static List<String> tunnel({bool wifi = false}) => [
    'tunnel',
    if (wifi) '--wifi',
  ];

  /// A team key passes [issuerId]; an individual key leaves it out
  /// (feature 015).
  static List<String> authApiKey({
    String? issuerId,
    required String keyId,
    required String privateKeyPath,
  }) => [
    'auth',
    if (_set(issuerId)) ...['--issuer-id', issuerId!.trim()],
    '--key-id',
    keyId.trim(),
    '--private-key',
    privateKeyPath,
  ];

  static List<String> authClean() => const ['auth', 'clean'];

  /// studio: 026 — what is saved about signing in; reads files only.
  static List<String> authStatus() => const ['auth', 'status', '--json'];

  // Features 027 and 028: run in the project folder, so no --project.
  static List<String> permissionsList() => const [
    'permissions',
    'list',
    '--json',
  ];

  static List<String> permissionSet(String key, String sentence) => [
    'permissions',
    'set',
    key,
    sentence,
    '--json',
  ];

  static List<String> permissionRemove(String key) => [
    'permissions',
    'remove',
    key,
    '--json',
  ];

  static List<String> capabilitiesList() => const [
    'capabilities',
    'list',
    '--json',
  ];

  static List<String> capabilityAdd(
    String id, [
    List<String> values = const [],
  ]) => [
    'capabilities',
    'add',
    id,
    for (final value in values) ...['--value', value],
    '--json',
  ];

  static List<String> capabilityRemove(
    String id, [
    List<String> values = const [],
  ]) => [
    'capabilities',
    'remove',
    id,
    for (final value in values) ...['--value', value],
    '--json',
  ];

  static List<String> pluginStatus() => const ['plugin', 'status', '--json'];

  /// Rewrites the draft of [plugin] after a backup (`plugin shim --force`).
  static List<String> pluginRegenerate(String plugin) => [
    'plugin',
    'shim',
    plugin,
    '--force',
  ];

  static List<String> pluginAck(String plugin) => [
    'plugin',
    'ack',
    plugin,
    '--json',
  ];

  static List<String> pluginList(String project) => [
    'plugin',
    'list',
    '--project',
    project,
  ];

  static List<String> pluginShim(
    String plugin, {
    required String project,
    bool force = false,
  }) => ['plugin', 'shim', plugin, '--project', project, if (force) '--force'];

  /// [command] for display: secrets (`--password`) replaced by `••••`.
  static String display(List<String> command) {
    final shown = <String>[];
    for (var i = 0; i < command.length; i++) {
      final part = command[i];
      final sensitive = const {
        '--password',
        '--token',
        '--secret',
        '--api-key',
      };
      final equals = part.indexOf('=');
      if (equals > 0 && sensitive.contains(part.substring(0, equals))) {
        shown.add('${part.substring(0, equals)}=••••');
      } else {
        shown.add(part);
      }
      if (sensitive.contains(part) && i + 1 < command.length) {
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
