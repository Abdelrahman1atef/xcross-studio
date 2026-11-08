// studio: 030 — the App Store Connect accounts the user signed in with, so
// switching between teams is one click.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../cli/xcross_events.dart';

/// One App Store Connect API key the user has used. Only what identifies it
/// is kept: the Key ID, the Issuer ID and where the `.p8` file is. Never the
/// key's contents and never a password (Apple ID sessions are not kept here:
/// switching to one needs the password again).
@immutable
class SigningAccount {
  const SigningAccount({
    required this.name,
    required this.keyId,
    required this.privateKeyPath,
    this.issuerId,
    this.note,
    this.lastUsed,
  });

  factory SigningAccount.fromJson(Map<String, Object?> json) {
    String? text(String key) => switch (json[key]) {
      final String value when value.trim().isNotEmpty => value.trim(),
      _ => null,
    };
    final keyId = text('keyId');
    final path = text('privateKeyPath');
    if (keyId == null || path == null) {
      throw const FormatException('A saved account needs a key ID and file.');
    }
    return SigningAccount(
      name: text('name') ?? keyId,
      keyId: keyId,
      privateKeyPath: path,
      issuerId: text('issuerId'),
      note: text('note'),
      lastUsed: DateTime.tryParse(text('lastUsed') ?? ''),
    );
  }

  /// What the user calls it ("Car wash team"); the Key ID until renamed.
  final String name;
  final String keyId;
  final String privateKeyPath;

  /// `null` for an individual key, which signs without one.
  final String? issuerId;
  final String? note;
  final DateTime? lastUsed;

  bool get isIndividual => issuerId == null;

  /// Whether the `.p8` file is still where it was.
  bool get fileExists => File(privateKeyPath).existsSync();

  /// Whether [key], as `xcross auth status` reports it, is this account.
  bool isSavedKey(SavedApiKey? key) => key != null && key.keyId == keyId;

  SigningAccount copyWith({
    String? name,
    String? note,
    String? privateKeyPath,
    DateTime? lastUsed,
  }) => SigningAccount(
    name: name ?? this.name,
    keyId: keyId,
    privateKeyPath: privateKeyPath ?? this.privateKeyPath,
    issuerId: issuerId,
    note: note ?? this.note,
    lastUsed: lastUsed ?? this.lastUsed,
  );

  Map<String, Object?> toJson() => {
    'name': name,
    'keyId': keyId,
    'issuerId': issuerId,
    'privateKeyPath': privateKeyPath,
    'note': note,
    'lastUsed': lastUsed?.toUtc().toIso8601String(),
  };
}

/// The saved accounts, in `<config>/signing-accounts.json`. Signing itself
/// stays with the CLI: [XcrossCommands.authApiKey] switches, this only
/// remembers.
class SigningAccounts extends ChangeNotifier {
  SigningAccounts({this.file, List<SigningAccount> accounts = const []})
    : _accounts = [...accounts];

  /// `null` keeps the accounts in memory only (tests).
  final File? file;
  final List<SigningAccount> _accounts;

  /// Reads [directory]'s `signing-accounts.json`. [importFrom], a
  /// `key-profiles.json` written by the `xcross-key` script, is read once
  /// when there is no file yet.
  static Future<SigningAccounts> load(
    String directory, {
    File? importFrom,
  }) async {
    final file = File(p.join(directory, 'signing-accounts.json'));
    final accounts = SigningAccounts(file: file);
    try {
      if (file.existsSync()) {
        accounts._accounts.addAll(
          _readAccounts(jsonDecode(await file.readAsString())),
        );
      } else if (importFrom != null && importFrom.existsSync()) {
        accounts._accounts.addAll(
          readScriptProfiles(jsonDecode(await importFrom.readAsString())),
        );
        if (accounts._accounts.isNotEmpty) await accounts._save();
      }
    } on Object {
      // First run or an unreadable file: start empty, never block the app.
    }
    return accounts;
  }

  static List<SigningAccount> _readAccounts(Object? json) => [
    if (json is Map && json['accounts'] is List)
      for (final entry in json['accounts'] as List)
        if (entry is Map<String, Object?>) ?_tryAccount(entry),
  ];

  static SigningAccount? _tryAccount(Map<String, Object?> json) {
    try {
      return SigningAccount.fromJson(json);
    } on FormatException {
      return null;
    }
  }

  /// The profiles of `%APPDATA%\xcross\key-profiles.json`:
  /// `{"profiles": {name: {keyId, issuerId, privateKey, note}}}`.
  @visibleForTesting
  static List<SigningAccount> readScriptProfiles(Object? json) => [
    if (json is Map && json['profiles'] is Map)
      for (final MapEntry(:key, :value) in (json['profiles'] as Map).entries)
        if (value is Map)
          ?_tryAccount({
            'name': '$key',
            'keyId': value['keyId'],
            'issuerId': value['issuerId'],
            'privateKeyPath': value['privateKey'],
            'note': value['note'],
          }),
  ];

  /// Most recently used first; never used ones by name.
  List<SigningAccount> get accounts => [..._accounts]
    ..sort((a, b) {
      final byUse = (b.lastUsed ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(a.lastUsed ?? DateTime.fromMillisecondsSinceEpoch(0));
      return byUse != 0 ? byUse : a.name.compareTo(b.name);
    });

  /// The account whose key `xcross auth status` reports as saved.
  SigningAccount? current(SavedApiKey? saved) =>
      _accounts.where((account) => account.isSavedKey(saved)).firstOrNull;

  /// Adds the signed-in [key], or refreshes the one with its Key ID (the
  /// name and note are kept). Ignores a key that could not be read.
  void remember(SavedApiKey key, {DateTime? now}) {
    final keyId = key.keyId;
    final path = key.privateKeyPath;
    if (key.problem != null ||
        keyId == null ||
        keyId.isEmpty ||
        path == null ||
        path.isEmpty) {
      return;
    }
    final at = now ?? DateTime.now();
    final index = _accounts.indexWhere((a) => a.keyId == keyId);
    final account = index < 0
        ? SigningAccount(
            name: keyId,
            keyId: keyId,
            privateKeyPath: path,
            issuerId: key.isIndividual ? null : key.issuerId,
            lastUsed: at,
          )
        : _accounts[index].copyWith(privateKeyPath: path, lastUsed: at);
    if (index < 0) {
      _accounts.add(account);
    } else if (_sameAs(_accounts[index], account)) {
      return; // nothing changed: no save, no rebuild
    } else {
      _accounts[index] = account;
    }
    _changed();
  }

  /// Two stamps within a minute are one use, so a re-check does not save.
  static bool _sameAs(SigningAccount a, SigningAccount b) =>
      a.privateKeyPath == b.privateKeyPath &&
      a.lastUsed != null &&
      b.lastUsed != null &&
      b.lastUsed!.difference(a.lastUsed!).abs() < const Duration(minutes: 1);

  void markUsed(SigningAccount account, {DateTime? now}) {
    final index = _accounts.indexWhere((a) => a.keyId == account.keyId);
    if (index < 0) return;
    _accounts[index] = _accounts[index].copyWith(
      lastUsed: now ?? DateTime.now(),
    );
    _changed();
  }

  void rename(SigningAccount account, String name, {String? note}) {
    final index = _accounts.indexWhere((a) => a.keyId == account.keyId);
    final trimmed = name.trim();
    if (index < 0 || trimmed.isEmpty) return;
    _accounts[index] = _accounts[index].copyWith(
      name: trimmed,
      note: note?.trim(),
    );
    _changed();
  }

  /// Forgets the account. The `.p8` file and Apple's key are not touched.
  void remove(SigningAccount account) {
    if (_accounts.any((a) => a.keyId == account.keyId)) {
      _accounts.removeWhere((a) => a.keyId == account.keyId);
      _changed();
    }
  }

  /// Completes when the last save has been written (tests wait for it).
  Future<void> get saved => _saving;
  Future<void> _saving = Future.value();

  void _changed() {
    notifyListeners();
    _saving = _saving.then((_) => _save());
  }

  Future<void> _save() async {
    final target = file;
    if (target == null) return;
    try {
      await target.parent.create(recursive: true);
      await target.writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'version': 1,
          'accounts': [for (final a in _accounts) a.toJson()],
        }),
      );
    } on FileSystemException {
      // A history is a convenience; a read-only profile must not break the app.
    }
  }
}
