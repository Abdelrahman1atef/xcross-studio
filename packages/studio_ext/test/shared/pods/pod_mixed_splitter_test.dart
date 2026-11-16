import 'dart:io';

import 'package:studio_ext/src/shared/pods/pod_mixed_splitter.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('pod-mixed-test-');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('AC-046-12 Mixed pods direction detection and splitting', () {
    const splitter = PodMixedSplitter(
      directoryFactory: Directory.new,
      fileFactory: File.new,
    );

    test(
      'Try 2.1.1 spike: Swift uses ObjC only generates @_exported import',
      () {
        final result = splitter.split(
          packageDir: tempDir,
          pod: 'Try',
          module: 'Try',
          objcSources: const ['Sources/TryHelper.m'],
          swiftSources: const ['Sources/Try.swift'],
          filesContent: const {
            'Sources/TryHelper.h': '''
#import <Foundation/Foundation.h>
@interface TryHelper : NSObject
+ (BOOL)catchException:(void(^)(void))tryBlock error:(NSError **)error;
@end
''',
            'Sources/TryHelper.m': '''
#import "TryHelper.h"
@implementation TryHelper
+ (BOOL)catchException:(void(^)(void))tryBlock error:(NSError **)error { return YES; }
@end
''',
            'Sources/Try.swift': '''
import Foundation
public func trap(block: () -> Void) throws {
    var error: NSError?
    TryHelper.catchException(block, error: &error)
}
''',
          },
        );

        expect(result.direction, PodMixedDirection.swiftUsesObjc);
        expect(result.objcTarget, 'TryObjC');
        expect(result.swiftTarget, 'Try');
        expect(result.isSupported, isTrue);

        final exportedFile = File(
          '${tempDir.path}/Sources/Try/Try_Exported.swift',
        );
        expect(exportedFile.existsSync(), isTrue);
        expect(
          exportedFile.readAsStringSync(),
          contains('@_exported import TryObjC'),
        );
      },
    );

    test(
      'Braintree 5.6.3 spike: ObjC uses Swift patches -Swift.h and creates bridging header',
      () {
        final result = splitter.split(
          packageDir: tempDir,
          pod: 'Braintree',
          module: 'Braintree',
          objcSources: const ['Sources/BTPayPalDriver.m'],
          swiftSources: const ['Sources/PayPalDriver.swift'],
          filesContent: const {
            'Sources/BTDriver.h': '''
#import <Foundation/Foundation.h>
@interface BTDriver : NSObject
@end
''',
            'Sources/BTPayPalDriver.m': '''
#import "BTDriver.h"
#import <Braintree/Braintree-Swift.h>
@implementation BTPayPalDriver
@end
''',
            'Sources/PayPalDriver.swift': '''
import Foundation
@objc public class PayPalDriver: NSObject {}
''',
          },
        );

        expect(result.direction, PodMixedDirection.objcUsesSwift);
        expect(result.objcTarget, 'Braintree');
        expect(result.swiftTarget, 'Braintree_swift');
        expect(result.isSupported, isTrue);
        expect(result.bridgingHeader, 'Braintree_swift-Bridging.h');

        final patchedFile = File('${tempDir.path}/Sources/BTPayPalDriver.m');
        expect(patchedFile.existsSync(), isTrue);
        expect(
          patchedFile.readAsStringSync(),
          contains('@import Braintree_swift;'),
        );

        final bridgingFile = File(
          '${tempDir.path}/Sources/Braintree_swift/Braintree_swift-Bridging.h',
        );
        expect(bridgingFile.existsSync(), isTrue);
        expect(
          bridgingFile.readAsStringSync(),
          contains('#import "BTDriver.h"'),
        );
      },
    );

    test('Two-way cyclic dependency returns objc_uses_own_swift rejection', () {
      final result = splitter.split(
        packageDir: tempDir,
        pod: 'CyclicPod',
        module: 'CyclicPod',
        objcSources: const ['Sources/ObjCPart.m'],
        swiftSources: const ['Sources/SwiftPart.swift'],
        filesContent: const {
          'Sources/ObjCPart.h': '''
@interface ObjCClass : NSObject
@end
''',
          'Sources/ObjCPart.m': '''
#import "ObjCPart.h"
#import <CyclicPod/CyclicPod-Swift.h>
@interface ObjCClass ()
@property (nonatomic, strong) SwiftClass *swiftObj;
@end
''',
          'Sources/SwiftPart.swift': '''
import Foundation
public class SwiftClass: NSObject {
    public var objcProp: ObjCClass?
}
''',
        },
      );

      expect(result.direction, PodMixedDirection.cyclic);
      expect(result.isSupported, isFalse);
      expect(result.reason, 'pod.objc_uses_own_swift');
    });

    test(
      'AC-046-13 Consumer @import of mixed pod is patched to include ObjC module',
      () {
        const consumerSource = '''
#import <UIKit/UIKit.h>
@import Try;

@implementation MyConsumer
- (void)doSomething {}
@end
''';

        final patched = PodMixedSplitter.patchObjcConsumerImports(
          consumerSource,
          const {'Try'},
        );

        expect(patched, isNotNull);
        expect(patched, contains('@import Try;\n@import TryObjC;'));

        final secondPatch = PodMixedSplitter.patchObjcConsumerImports(
          patched!,
          const {'Try'},
        );
        expect(secondPatch, isNull);
      },
    );
  });
}
