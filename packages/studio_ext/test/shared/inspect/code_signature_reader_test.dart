import 'dart:typed_data';

import 'package:studio_ext/src/shared/inspect/code_signature_reader.dart';
import 'package:studio_ext/src/shared/inspect/inspect_report.dart';
import 'package:studio_ext/src/shared/inspect/macho_reader.dart';
import 'package:test/test.dart';

import '../../support/fixture_builder.dart';

void main() {
  CodeSignatureInfo read(Uint8List bytes) =>
      readCodeSignature(bytes, readMachO(bytes).preferredSlice);

  test('unsigned binary has kind none', () {
    final info = read(machO());
    expect(info.kind, SignatureKind.none);
    expect(info.entitlements, isNull);
  });

  test('linker-signed ad-hoc binary', () {
    final info = read(
      machO(signature: codeSignature(identifier: 'a.b', flags: 0x20002)),
    );
    expect(info.kind, SignatureKind.adhoc);
    expect(info.linkerSigned, isTrue);
    expect(info.identifier, 'a.b');
    expect(info.teamId, isNull);
  });

  test('ad-hoc with XML entitlements exposes aps-environment', () {
    final info = read(
      machO(
        signature: codeSignature(
          entitlements: {
            'aps-environment': 'development',
            'b': [1],
          },
        ),
      ),
    );
    expect(info.kind, SignatureKind.adhoc);
    expect(info.linkerSigned, isFalse);
    expect(info.entitlements, {
      'aps-environment': 'development',
      'b': [1],
    });
    expect(info.entitlements!.keys.toList(), ['aps-environment', 'b']);
  });

  test('DER-only entitlements are reported as present but not decoded', () {
    final info = read(machO(signature: codeSignature(derEntitlements: true)));
    expect(info.derEntitlementsPresent, isTrue);
    expect(info.entitlements, isNull);
  });

  test('non-empty CMS blob means certificate; team id is read', () {
    final info = read(
      machO(
        signature: codeSignature(
          teamId: 'TEAMID1234',
          flags: 0,
          cms: CmsBlob.signed,
        ),
      ),
    );
    expect(info.kind, SignatureKind.certificate);
    expect(info.teamId, 'TEAMID1234');
  });

  test('empty CMS blob is still ad-hoc', () {
    final info = read(machO(signature: codeSignature(cms: CmsBlob.empty)));
    expect(info.kind, SignatureKind.adhoc);
  });

  test('unreadable entitlements blob is flagged', () {
    final info = read(
      machO(signature: codeSignature(corruptEntitlements: true)),
    );
    expect(info.entitlementsUnreadable, isTrue);
    expect(info.entitlements, isNull);
  });

  test('malformed SuperBlob is flagged and treated as ad-hoc', () {
    final bogus = Uint8List.fromList(List.filled(32, 0x11));
    final info = read(machO(signature: bogus));
    expect(info.malformed, isTrue);
    expect(info.kind, SignatureKind.adhoc);
  });
}
