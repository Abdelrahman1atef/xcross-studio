# Configuration

[← xcross README](../../README.md) · [All guides](README.md)

By default xcross takes the world as it finds it: whatever is on `PATH`. One optional YAML file changes that. Declare where Swift, LLVM, Flutter, and the SDK actually live, and every command - plus every process it spawns, including IDE launches - is rebuilt around that declaration before anything compiles.

It is read from `XCROSS_CONFIG`, else `config.yaml`/`config.yml` under the platform xcross config directory. Configured executables win and must be real executable paths; everything unspecified (`git`, device utilities, system commands) still resolves through the invoking `PATH`. `environment.PATH` prepends its entries to that inherited `PATH` for child processes. No file means nothing changes.

```yaml
toolchains:
  swift: /absolute/swift/bin
  llvm:
    - /absolute/clang/bin
    - /absolute/lld/bin
    - /absolute/llvm/bin
roots:
  darwinSdk: /absolute/path/to/xcross-darwin.artifactbundle
  flutterSdk: /absolute/path/to/flutter
  xcross: /absolute/path/to/xcross
  javaHome: /absolute/path/to/jdk
  konanData: /absolute/path/to/konan-data
environment:
  PATH:
    - /absolute/toolchain/bin
setup: https://raw.githubusercontent.com/Abdelrahman1atef/xcross-studio/main/setup/apt.sh
```

Edit it with `xcross config`, inspect it with `xcross config show`, prove it with `xcross config validate`.

`setup` makes `xcross setup` run that script (an absolute path or an HTTP(S) URL) instead of its built-in installer. Before running anything, xcross prints the script's name, source, and SHA-256 and asks for confirmation. Pass `--yes` to skip the prompt, which is required when there is no terminal. Remote scripts are cached by content hash, and `xcross update` refreshes them.

**Full reference: [xcross.sh/docs/configuration](https://xcross.sh/docs/configuration)** - every key, discovery order, variable expansion, and the runtime overlay.
