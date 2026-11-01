import 'dart:io';

import 'package:cli_kit/shared/platform/platform_host.dart';

/// `HostFileSystemInterface` over `dart:io` for tests.
///
/// With [longPathPrefix] on Windows, paths get the `\\?\` prefix that the
/// production `WindowsFileSystem` adds, so path handling is tested against the
/// same shapes the CLI sees.
final class IoFileSystem implements HostFileSystemInterface {
  const IoFileSystem({this.longPathPrefix = false});

  final bool longPathPrefix;

  String _io(String path) {
    if (!longPathPrefix || !Platform.isWindows || path.startsWith(r'\\?\')) {
      return path;
    }
    return r'\\?\' + File(path).absolute.path.replaceAll('/', r'\');
  }

  @override
  File file(String path) => File(_io(path));

  @override
  Directory directory(String path) => Directory(_io(path));

  @override
  Link link(String path) => Link(_io(path));

  @override
  void makeExecutable(String path) {}

  @override
  void setPermissions(String path, int mode) {}

  @override
  Future<void> createArchiveLink(String destination, String target) =>
      Link(_io(destination)).create(target);
}
