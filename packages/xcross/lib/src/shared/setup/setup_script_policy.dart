import 'dart:io';
import 'package:meta/meta.dart';

/// A built-in setup script for one package manager.
@internal
typedef DefaultSetupScript = ({
  /// Package manager name, as accepted by `xcross setup --manager`.
  String manager,

  /// HTTP(S) URL or absolute path of the script.
  String source,

  /// The script's text when it is compiled into xcross; then [source] is
  /// only where the same script is published, and nothing is downloaded.
  String? embedded,
});

@internal
abstract interface class SetupScriptPolicy {
  /// Built-in scripts `xcross setup` can run when the config names none, in
  /// preference order, limited to package managers present on this host.
  /// Empty means the host uses its in-process requirement installer.
  Future<List<DefaultSetupScript>> defaultSources();

  /// The built-in script for [manager] (one of [supportedManagers]), or null
  /// when that package manager is not installed.
  Future<DefaultSetupScript?> sourceFor(String manager);

  /// Every package manager this host has a built-in script for.
  List<String> get supportedManagers;

  /// What the built-in scripts can install one at a time, as accepted by
  /// `xcross setup --only` (forwarded as `XCROSS_SETUP_ONLY`). Empty when
  /// the host has no built-in scripts.
  List<String> get components;

  File cachedFile(String digest);
  File cachePointer(String digest);
  Future<({String executable, List<String> arguments})> invocation(String path);
  void replace(File temporary, File destination);
}
