import 'dart:typed_data';

import 'package:studio_ext/src/shared/inspect/macho_reader.dart';
import 'package:test/test.dart';

import '../../support/fixture_builder.dart';

void main() {
  test('reads a thin 64-bit arm64 executable without a signature', () {
    final info = readMachO(machO());
    expect(info.architectures, ['arm64']);
    expect(info.preferredSlice.hasCodeSignature, isFalse);
  });

  test('reads a thin 32-bit armv7 executable', () {
    expect(readMachO(machO(arch: 'armv7')).architectures, ['armv7']);
  });

  test('locates LC_CODE_SIGNATURE', () {
    final signature = codeSignature();
    final bytes = machO(signature: signature);
    final slice = readMachO(bytes).preferredSlice;
    expect(slice.codeSignatureSize, signature.length);
    expect(
      bytes.sublist(
        slice.codeSignatureOffset!,
        slice.codeSignatureOffset! + slice.codeSignatureSize!,
      ),
      signature,
    );
  });

  test('reads 32-bit and 64-bit fat headers and prefers arm64', () {
    final slices = [machO(arch: 'armv7'), machO(signature: codeSignature())];
    for (final wide in [false, true]) {
      final info = readMachO(fatMachO(slices, wide: wide));
      expect(info.architectures, ['armv7', 'arm64']);
      expect(info.preferredSlice.architecture, 'arm64');
      expect(info.preferredSlice.hasCodeSignature, isTrue);
      expect(info.preferredSlice.offset, greaterThan(0));
    }
  });

  test('reads a byte-swapped (big-endian) thin header', () {
    final bytes = machO();
    final data = ByteData.sublistView(bytes);
    for (var offset = 0; offset < 32; offset += 4) {
      data.setUint32(offset, data.getUint32(offset, Endian.little));
    }
    expect(readMachO(bytes).architectures, ['arm64']);
  });

  test('names arm64e and unknown CPUs', () {
    expect(readMachO(machO(arch: 'arm64e')).architectures, ['arm64e']);
    expect(architectureName(18, 0), 'cpu:18/0');
  });

  test('rejects truncated and non-Mach-O input', () {
    expect(() => readMachO(machO().sublist(0, 20)), throwsFormatException);
    final signed = machO(signature: codeSignature());
    expect(
      () => readMachO(signed.sublist(0, signed.length - 10)),
      throwsFormatException,
    );
    expect(
      () => readMachO(Uint8List.fromList(List.filled(64, 0x41))),
      throwsFormatException,
    );
  });

  test('hasMachOMagic recognises thin and fat magics only', () {
    expect(hasMachOMagic(machO()), isTrue);
    expect(hasMachOMagic(fatMachO([machO()])), isTrue);
    expect(hasMachOMagic(fakePng), isFalse);
  });
}
