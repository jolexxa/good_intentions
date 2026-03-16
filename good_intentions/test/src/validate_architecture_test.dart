import 'dart:io';

import 'package:good_intentions/good_intentions.dart';
import 'package:hooks/hooks.dart';
import 'package:intentions_engine/intentions_engine.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('ArchitectureReport', () {
    test('hasErrors returns true when error results present', () {
      final report = ArchitectureReport(
        classes: const [],
        untagged: const [],
        graph: DependencyGraph(const []),
        results: const [
          ValidationResult(severity: Severity.error, message: 'bad'),
        ],
        puml: '',
      );

      expect(report.hasErrors, isTrue);
      expect(report.errors, hasLength(1));
    });

    test('hasErrors returns false when no error results', () {
      final report = ArchitectureReport(
        classes: const [],
        untagged: const [],
        graph: DependencyGraph(const []),
        results: const [
          ValidationResult(severity: Severity.warning, message: 'hmm'),
          ValidationResult(severity: Severity.ok, message: 'fine'),
        ],
        puml: '',
      );

      expect(report.hasErrors, isFalse);
      expect(report.errors, isEmpty);
    });

    test('hasErrors returns false for empty results', () {
      final report = ArchitectureReport(
        classes: const [],
        untagged: const [],
        graph: DependencyGraph(const []),
        results: const [],
        puml: '',
      );

      expect(report.hasErrors, isFalse);
    });
  });

  group('analyzeArchitecture', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('validate_arch_test_');

      // Write a minimal pubspec so _readPackageName works.
      File(p.join(tmpDir.path, 'pubspec.yaml')).writeAsStringSync(
        'name: test_pkg\n',
      );

      ClassCollector.collectOverride = (_) async => (
            const [
              AnnotatedClass(
                name: 'Repo',
                intention: Intention.repository,
                dependencies: {'Api'},
              ),
              AnnotatedClass(
                name: 'Api',
                intention: Intention.dataSource,
                dependencies: {},
              ),
            ],
            const <String>['Untagged'],
          );
    });

    tearDown(() {
      ClassCollector.collectOverride = null;
      tmpDir.deleteSync(recursive: true);
    });

    test('returns report with classes and validation', () async {
      final report = await analyzeArchitecture(
        packageRoot: tmpDir.path,
        packageName: 'test_pkg',
      );

      expect(report.classes, hasLength(2));
      expect(report.hasErrors, isFalse);
      expect(report.untagged, contains('Untagged'));
      expect(report.puml, contains('@startuml'));
      expect(report.puml, contains('Repo --> Api'));
    });

    test('detects architecture violations', () async {
      ClassCollector.collectOverride = (_) async => (
            const [
              AnnotatedClass(
                name: 'MyCubit',
                intention: Intention.viewModel,
                dependencies: {},
              ),
              AnnotatedClass(
                name: 'BadApi',
                intention: Intention.dataSource,
                dependencies: {'MyCubit'},
              ),
            ],
            const <String>[],
          );

      final report = await analyzeArchitecture(
        packageRoot: tmpDir.path,
        packageName: 'test_pkg',
      );

      expect(report.hasErrors, isTrue);
      expect(report.errors.first.message, contains('BadApi'));
    });

    test('reads package name from pubspec when not provided', () async {
      final report = await analyzeArchitecture(packageRoot: tmpDir.path);

      expect(report.puml, contains('test_pkg'));
    });
  });

  group('reportResults', () {
    test('writes untagged warnings', () {
      final report = ArchitectureReport(
        classes: const [],
        untagged: const ['Foo', 'Bar'],
        graph: DependencyGraph(const []),
        results: const [],
        puml: '',
      );
      final buf = StringBuffer();

      reportResults(report, buf);

      expect(buf.toString(), contains('[!] Foo has no intention annotation.'));
      expect(buf.toString(), contains('[!] Bar has no intention annotation.'));
    });

    test('writes error results', () {
      final report = ArchitectureReport(
        classes: const [],
        untagged: const [],
        graph: DependencyGraph(const []),
        results: const [
          ValidationResult(severity: Severity.error, message: 'bad dep'),
        ],
        puml: '',
      );
      final buf = StringBuffer();

      reportResults(report, buf);

      expect(buf.toString(), contains('[ERROR] bad dep'));
    });

    test('writes warning results', () {
      final report = ArchitectureReport(
        classes: const [],
        untagged: const [],
        graph: DependencyGraph(const []),
        results: const [
          ValidationResult(severity: Severity.warning, message: 'hmm'),
        ],
        puml: '',
      );
      final buf = StringBuffer();

      reportResults(report, buf);

      expect(buf.toString(), contains('[WARN] hmm'));
    });

    test('writes info results', () {
      final report = ArchitectureReport(
        classes: const [],
        untagged: const [],
        graph: DependencyGraph(const []),
        results: const [
          ValidationResult(severity: Severity.info, message: 'fyi'),
        ],
        puml: '',
      );
      final buf = StringBuffer();

      reportResults(report, buf);

      expect(buf.toString(), contains('[INFO] fyi'));
    });

    test('skips ok results', () {
      final report = ArchitectureReport(
        classes: const [],
        untagged: const [],
        graph: DependencyGraph(const []),
        results: const [
          ValidationResult(severity: Severity.ok, message: 'fine'),
        ],
        puml: '',
      );
      final buf = StringBuffer();

      reportResults(report, buf);

      expect(buf.toString(), isEmpty);
    });
  });

  group('validateArchitecture', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('validate_test_');
      File(p.join(tmpDir.path, 'pubspec.yaml')).writeAsStringSync(
        'name: test_pkg\n',
      );
    });

    tearDown(() {
      ClassCollector.collectOverride = null;
      tmpDir.deleteSync(recursive: true);
    });

    test('runs validation and writes puml in test mode', () async {
      ClassCollector.collectOverride = (_) async => (
            const [
              AnnotatedClass(
                name: 'TestApi',
                intention: Intention.dataSource,
                dependencies: {},
              ),
            ],
            const <String>[],
          );

      await validateArchitecture(
        [],
        packageRoot: tmpDir.path,
        packageName: 'test_pkg',
      );

      final pumlFile = File(p.join(tmpDir.path, 'lib', 'architecture.g.puml'));
      expect(pumlFile.existsSync(), isTrue);
      expect(pumlFile.readAsStringSync(), contains('@startuml'));
    });

    test('throws BuildError on architecture violations', () async {
      ClassCollector.collectOverride = (_) async => (
            const [
              AnnotatedClass(
                name: 'MyCubit',
                intention: Intention.viewModel,
                dependencies: {},
              ),
              AnnotatedClass(
                name: 'BadApi',
                intention: Intention.dataSource,
                dependencies: {'MyCubit'},
              ),
            ],
            const <String>[],
          );

      expect(
        () => validateArchitecture(
          [],
          packageRoot: tmpDir.path,
          packageName: 'test_pkg',
        ),
        throwsA(isA<BuildError>()),
      );
    });
  });
}
