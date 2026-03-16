import 'package:good_intentions/good_intentions.dart';
import 'package:intentions_engine/intentions_engine.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

void main() {
  group('ValidationReporter', () {
    group('validateAll', () {
      test('returns results for all dependency edges', () {
        const api = AnnotatedClass(
          name: 'Api',
          intention: Intention.dataSource,
          dependencies: {},
        );
        const repo = AnnotatedClass(
          name: 'Repo',
          intention: Intention.repository,
          dependencies: {'Api'},
        );
        final graph = DependencyGraph([api, repo]);

        final results = ValidationReporter.validateAll(graph);

        expect(results, hasLength(1));
        expect(results.first.severity, Severity.ok);
      });

      test('skips unknown dependencies', () {
        const repo = AnnotatedClass(
          name: 'Repo',
          intention: Intention.repository,
          dependencies: {'Ghost'},
        );
        final graph = DependencyGraph([repo]);

        final results = ValidationReporter.validateAll(graph);

        expect(results, isEmpty);
      });

      test('detects upward dependency errors', () {
        const api = AnnotatedClass(
          name: 'Api',
          intention: Intention.dataSource,
          dependencies: {'VM'},
        );
        const vm = AnnotatedClass(
          name: 'VM',
          intention: Intention.viewModel,
          dependencies: {},
        );
        final graph = DependencyGraph([api, vm]);

        final results = ValidationReporter.validateAll(graph);

        expect(results, hasLength(1));
        expect(results.first.severity, Severity.error);
      });

      test('returns empty for no edges', () {
        const api = AnnotatedClass(
          name: 'Api',
          intention: Intention.dataSource,
          dependencies: {},
        );
        final graph = DependencyGraph([api]);

        final results = ValidationReporter.validateAll(graph);

        expect(results, isEmpty);
      });
    });

    group('report', () {
      late Logger logger;
      late List<LogRecord> records;

      setUp(() {
        hierarchicalLoggingEnabled = true;
        logger = Logger('test.${DateTime.now().microsecondsSinceEpoch}');
        records = <LogRecord>[];
        logger.onRecord.listen(records.add);
        logger.level = Level.ALL;
      });

      test('logs warnings', () {
        final results = [
          const ValidationResult(
            severity: Severity.warning,
            message: 'watch out',
          ),
        ];

        final hasErrors = ValidationReporter.report(results, logger);

        expect(hasErrors, isFalse);
        expect(records, hasLength(1));
        expect(records.first.level, Level.WARNING);
        expect(records.first.message, 'watch out');
      });

      test('logs errors and returns true', () {
        final results = [
          const ValidationResult(
            severity: Severity.error,
            message: 'bad stuff',
          ),
        ];

        final hasErrors = ValidationReporter.report(results, logger);

        expect(hasErrors, isTrue);
        expect(records, hasLength(1));
        expect(records.first.level, Level.SEVERE);
      });

      test('skips ok results', () {
        final results = [
          const ValidationResult(
            severity: Severity.ok,
            message: 'all good',
          ),
        ];

        final hasErrors = ValidationReporter.report(results, logger);

        expect(hasErrors, isFalse);
        expect(records, isEmpty);
      });

      test('logs info results', () {
        final results = [
          const ValidationResult(
            severity: Severity.info,
            message: 'fyi',
          ),
        ];

        final hasErrors = ValidationReporter.report(results, logger);

        expect(hasErrors, isFalse);
        expect(records, hasLength(1));
        expect(records.first.level, Level.INFO);
        expect(records.first.message, 'fyi');
      });

      test('handles mixed results', () {
        final results = [
          const ValidationResult(severity: Severity.ok, message: 'fine'),
          const ValidationResult(
            severity: Severity.info,
            message: 'note',
          ),
          const ValidationResult(
            severity: Severity.warning,
            message: 'hmm',
          ),
          const ValidationResult(
            severity: Severity.error,
            message: 'nope',
          ),
        ];

        final hasErrors = ValidationReporter.report(results, logger);

        expect(hasErrors, isTrue);
        expect(records, hasLength(3));
      });
    });
  });
}
