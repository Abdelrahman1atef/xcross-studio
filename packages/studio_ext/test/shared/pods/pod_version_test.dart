import 'package:studio_ext/src/shared/pods/pod_version.dart';
import 'package:test/test.dart';

void main() {
  test('AC-046-1 parses every pod version in research section 3', () {
    const versions = [
      '10.0.0',
      '9.0.0',
      '3.5.0',
      '4.2.1',
      '1.0.0-beta8',
      '14.0.0',
      '7.0.0',
      '6.0.0',
      '10.1.1',
      '8.1.5',
      '3.30910.0',
      '2.4.1',
      '137.7151.04',
      '3.6.1b1',
      '3.7.0b1',
      '2.17.0',
      '9.30.0',
      '5.0.11',
      '2.0.164',
      '9.4.0',
      '5.6.3',
      '2.1.1',
      '3.11.4',
      '1.15.1',
      '5.3.0',
    ];
    for (final source in versions) {
      expect(PodVersion(source).source, source);
    }
    expect(PodRequirement('~> 2.0.152').allows(PodVersion('2.0.164')), isTrue);
  });

  test('AC-046-1 compares release and prerelease segments', () {
    expect(PodVersion('7.00.0').compareTo(PodVersion('7.0.0')), 0);
    expect(
      PodVersion('3.30910.0').compareTo(PodVersion('3.9.10')),
      greaterThan(0),
    );
    expect(
      PodVersion('1.0.0-beta8').compareTo(PodVersion('1.0.0')),
      lessThan(0),
    );
    expect(PodVersion('3.7.0b1').compareTo(PodVersion('3.7.0')), lessThan(0));
  });

  test('AC-046-1 evaluates all comparison operators and clauses', () {
    final version = PodVersion('2.3.4');
    for (final expression in [
      '= 2.3.4',
      '!= 2.3.5',
      '> 2.3.3',
      '< 2.3.5',
      '>= 2.3.4',
      '<= 2.3.4',
      '>= 2.0, < 3.0',
    ]) {
      expect(
        PodRequirement(expression).allows(version),
        isTrue,
        reason: expression,
      );
    }
    expect(PodRequirement('> 2.3.4').allows(version), isFalse);
  });

  test('AC-046-1 applies RubyGems pessimistic bounds', () {
    expect(PodRequirement('~> 6.3').allows(PodVersion('6.9')), isTrue);
    expect(PodRequirement('~> 6.3').allows(PodVersion('7.0')), isFalse);
    expect(PodRequirement('~> 6.0.3').allows(PodVersion('6.0.9')), isTrue);
    expect(PodRequirement('~> 6.0.3').allows(PodVersion('6.1')), isFalse);
  });

  test('AC-046-1 selects MobileVLCKit prerelease', () {
    final requirement = PodRequirement('~> 3.6.1b1');
    final versions = [
      '3.6.1b1',
      '3.7.0b1',
      '3.7.5',
    ].map(PodVersion.new).where(requirement.allows).toList();
    expect(versions.map((version) => version.source), ['3.6.1b1']);
    expect(PodRequirement('>= 1.0').allows(PodVersion('1.1-beta8')), isFalse);
    expect(
      PodRequirement('= 1.0.0-beta8').allows(PodVersion('1.0.0-beta8')),
      isTrue,
    );
  });
}
