import 'dart:convert';
import 'dart:io';

import 'package:studio_ext/src/shared/pods/pod_consumer.dart';
import 'package:test/test.dart';

void main() {
  const consumer = PodConsumer();

  test('AC-046-5 keeps root files and deduplicates iOS binaries', () {
    final view = consumer.build({
      'name': 'MyFatoorah',
      'version': '2.0.164',
      'source_files': ['Root.h'],
      'vendored_frameworks': ['SDK/MFSDK.xcframework'],
      'ios': {
        'vendored_frameworks': ['SDK/MFSDK.xcframework'],
      },
      'subspecs': [
        {
          'name': 'Core',
          'source_files': ['Core.m', 'Root.h'],
        },
      ],
    });
    expect(view.attributes['vendored_frameworks'], ['SDK/MFSDK.xcframework']);
    expect(view.attributes['source_files'], ['Root.h', 'Core.m']);
    expect(view.selectedSubspecs, ['Core']);
  });

  test('AC-046-5 inherits settings and excludes test specs', () {
    final view = consumer.build({
      'name': 'Example',
      'version': '1.0',
      'pod_target_xcconfig': {'OTHER_CFLAGS': '-DROOT'},
      'frameworks': ['Foundation'],
      'dependencies': {
        'MLKitCommon': ['~> 14.0'],
      },
      'subspecs': [
        {
          'name': 'Core',
          'pod_target_xcconfig': {'OTHER_CFLAGS': '-DCORE'},
          'frameworks': ['UIKit'],
          'dependencies': {
            'MLKitCommon': ['>= 14.0'],
          },
        },
        {
          'name': 'Tests',
          'test_specification': true,
          'source_files': ['Tests.m'],
        },
      ],
    });
    expect(view.attributes['pod_target_xcconfig'], {
      'OTHER_CFLAGS': '-DROOT -DCORE',
    });
    expect(view.attributes['frameworks'], ['Foundation', 'UIKit']);
    expect(view.attributes['dependencies'], {
      'MLKitCommon': ['~> 14.0', '>= 14.0'],
    });
    expect(view.selectedSubspecs, ['Core']);
  });

  test('AC-046-5 selects defaults or none', () {
    final root = <String, Object?>{
      'name': 'Example',
      'default_subspecs': 'Core',
      'subspecs': [
        {
          'name': 'Core',
          'source_files': ['Core.m'],
        },
        {
          'name': 'Extra',
          'source_files': ['Extra.m'],
        },
      ],
    };
    expect(consumer.build(root).selectedSubspecs, ['Core']);
    root['default_subspecs'] = ':none';
    expect(consumer.build(root).selectedSubspecs, isEmpty);
    expect(consumer.build(root, selected: ['Extra']).selectedSubspecs, [
      'Extra',
    ]);
  });

  test('AC-046-5 keeps root-only attributes and merges per-spec files', () {
    final view = consumer.build({
      'name': 'Example',
      'version': '1.0',
      'module_name': 'RootModule',
      'source': {'git': 'https://example.invalid/repo'},
      'source_files': ['Shared.h'],
      'resource_bundles': {
        'Models': ['root.bin'],
      },
      'subspecs': [
        {
          'name': 'Core',
          'module_name': 'WrongModule',
          'source_files': ['Shared.h', 'Core.m'],
          'resource_bundles': {
            'Models': ['core.bin'],
          },
        },
      ],
    });
    expect(view.attributes['module_name'], 'RootModule');
    expect(view.attributes['source'], {'git': 'https://example.invalid/repo'});
    expect(view.attributes['source_files'], ['Shared.h', 'Core.m']);
    expect(view.attributes['resource_bundles'], {
      'Models': ['root.bin', 'core.bin'],
    });
  });

  test('AC-046-5 selects nested iOS subspecs without test specs', () {
    final view = consumer.build({
      'name': 'TensorFlowLiteSwift',
      'subspecs': [
        {
          'name': 'Core',
          'source_files': ['Core.swift'],
          'subspecs': [
            {
              'name': 'Privacy',
              'source_files': ['Privacy.swift'],
            },
            {
              'name': 'SpecTests',
              'test_specification': true,
              'source_files': ['Test.swift'],
            },
            {
              'name': 'MacOnly',
              'platforms': {'osx': '10.15'},
              'source_files': ['Mac.swift'],
            },
          ],
        },
      ],
    });
    expect(view.selectedSubspecs, ['Core', 'Core/Privacy']);
    expect(view.attributes['source_files'], ['Core.swift', 'Privacy.swift']);
  });

  test('AC-046-5 reads the published GoogleMLKit 9.0.0 spec', () {
    final source = File(
      'test/fixtures/pods/google_mlkit_9.0.0.json',
    ).readAsStringSync();
    final spec = (jsonDecode(source) as Map<String, dynamic>)
        .cast<String, Object?>();
    final defaults = consumer.build(spec);
    expect(defaults.selectedSubspecs, ['Common']);
    final textRecognition = consumer.build(
      spec,
      selected: ['MLKitCore', 'TextRecognition'],
    );
    expect(textRecognition.selectedSubspecs, ['MLKitCore', 'TextRecognition']);
    expect(
      textRecognition.attributes['source_files'],
      contains('MLKitCore/Sources/MLKit.h'),
    );
    expect(
      textRecognition.attributes['dependencies']! as Map,
      contains('MLKitTextRecognition'),
    );
  });
}
