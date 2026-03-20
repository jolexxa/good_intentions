import 'package:good_intentions/good_intentions.dart';
import 'package:intentions_engine/intentions_engine.dart';
import 'package:test/test.dart';

void main() {
  late ValidationReporter reporter;

  setUp(() {
    reporter = ValidationReporter();
  });

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

        final results = reporter.validateAll(graph);

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

        final results = reporter.validateAll(graph);

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

        final results = reporter.validateAll(graph);

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

        final results = reporter.validateAll(graph);

        expect(results, isEmpty);
      });
    });
  });
}
