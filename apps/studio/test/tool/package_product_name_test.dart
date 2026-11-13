import 'package:flutter_test/flutter_test.dart';

import '../../tool/package.dart';

void main() {
  group('AC-RB-3 the packaging script takes the product name once', () {
    test('defaults to today\'s name', () {
      expect(productNameFrom(const [], const {}), 'XCross Studio');
    });

    test('reads PRODUCT_NAME from the environment', () {
      expect(
        productNameFrom(const [], const {'PRODUCT_NAME': 'Markab'}),
        'Markab',
      );
    });

    test('--product-name wins over the environment and ignores blanks', () {
      expect(
        productNameFrom(
          const ['--product-name=Faluka'],
          const {'PRODUCT_NAME': 'Markab'},
        ),
        'Faluka',
      );
      expect(
        productNameFrom(
          const ['--product-name= '],
          const {'PRODUCT_NAME': 'Markab'},
        ),
        'Markab',
      );
    });

    test('rewrites only the Name= line of the desktop entry', () {
      const entry =
          '[Desktop Entry]\nType=Application\nName=XCross Studio\n'
          'Exec=xcross-studio\nGenericName=iOS builds\n';
      final out = desktopEntryWithName(entry, 'Markab');
      expect(out, contains('\nName=Markab\n'));
      expect(out, contains('GenericName=iOS builds'));
      expect(out, isNot(contains('Name=XCross Studio')));
    });
  });
}
