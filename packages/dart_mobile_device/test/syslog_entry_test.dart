// studio: 010 — shared syslog line parser.
import 'package:dart_mobile_device/target/iphone/device/pymd/syslog_entry.dart';
import 'package:test/test.dart';

void main() {
  test('parses the pymobiledevice3 syslog live JSON shape', () {
    final entry = SyslogEntry.tryParse(
      '{"pid": 33, "procid": 33, "thread_id": 1893, '
      '"timestamp": "2026-11-01T16:55:51.018604", "level": "ERROR", '
      '"image_name": "/System/Library/Frameworks/CoreMotion.framework/CoreMotion", '
      '"filename": "/System/Library/CoreServices/SpringBoard", '
      '"message": "hello", "label": {"subsystem": "com.apple.x", "category": "y"}}',
    )!;
    expect(entry.pid, 33);
    expect(entry.process, 'SpringBoard');
    expect(entry.level, 'error');
    expect(entry.subsystem, 'com.apple.x');
    expect(entry.category, 'y');
    expect(entry.time, '2026-11-01T16:55:51.018604');
    expect(entry.message, 'hello');
  });

  test('non-entries give null; unknown levels become notice', () {
    expect(SyslogEntry.tryParse('not json'), isNull);
    expect(SyslogEntry.tryParse('{"message": "no pid"}'), isNull);
    expect(SyslogEntry.tryParse('[1]'), isNull);
    expect(
      SyslogEntry.tryParse(
        '{"pid": 1, "message": "m", "level": "Default"}',
      )!.level,
      'notice',
    );
  });
}
