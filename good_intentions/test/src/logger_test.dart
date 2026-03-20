import 'package:good_intentions/good_intentions.dart';
import 'package:test/test.dart';

void main() {
  late StringBuffer buf;
  late Logger logger;

  setUp(() {
    buf = StringBuffer();
    logger = Logger(buf);
  });

  group('Logger', () {
    test('info writes prefixed message', () {
      logger.info('hello');
      expect(buf.toString(), '${Logger.prefix} hello\n');
    });

    test('warn writes prefixed WARN message', () {
      logger.warn('careful');
      expect(buf.toString(), '${Logger.prefix} WARN: careful\n');
    });

    test('error writes prefixed ERROR message', () {
      logger.error('broken');
      expect(buf.toString(), '${Logger.prefix} ERROR: broken\n');
    });

    test('prefix is [good_intentions]', () {
      expect(Logger.prefix, '[good_intentions]');
    });

    test('multiple calls append to sink', () {
      logger
        ..info('first')
        ..warn('second')
        ..error('third');

      final output = buf.toString();
      expect(output, contains('${Logger.prefix} first'));
      expect(output, contains('${Logger.prefix} WARN: second'));
      expect(output, contains('${Logger.prefix} ERROR: third'));
    });
  });
}
