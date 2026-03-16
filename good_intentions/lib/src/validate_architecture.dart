import 'dart:io';

import 'package:good_intentions/src/class_collector.dart';
import 'package:good_intentions/src/puml_writer.dart';
import 'package:good_intentions/src/validation_reporter.dart';
import 'package:hooks/hooks.dart';
import 'package:intentions/intentions.dart' as annotations;
import 'package:intentions_engine/intentions_engine.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// The result of analyzing a package's architecture.
@annotations.model
class ArchitectureReport {
  /// Creates an architecture report.
  const ArchitectureReport({
    required this.classes,
    required this.untagged,
    required this.graph,
    required this.results,
    required this.puml,
  });

  /// All annotated classes discovered in the package and its dependencies.
  final List<AnnotatedClass> classes;

  /// Public, concrete class names with no intention annotation.
  final List<String> untagged;

  /// The dependency graph of annotated classes.
  final DependencyGraph graph;

  /// Validation results for all dependency edges.
  final List<ValidationResult> results;

  /// Generated PlantUML diagram source.
  final String puml;

  /// Whether any error-severity violations were found.
  bool get hasErrors => results.any((r) => r.severity == Severity.error);

  /// All error-severity violations.
  List<ValidationResult> get errors =>
      results.where((r) => r.severity == Severity.error).toList();
}

/// Validates architecture of the current package from a build hook.
///
/// Usage in `hook/build.dart`:
///
/// ```dart
/// import 'package:good_intentions/good_intentions.dart';
///
/// Future<void> main(List<String> args) async => validateArchitecture(args);
/// ```
///
/// In test mode, pass [packageRoot] and [packageName] to bypass the hooks
/// infrastructure and run validation directly.
Future<void> validateArchitecture(
  List<String> args, {
  @visibleForTesting String? packageRoot,
  @visibleForTesting String? packageName,
}) async {
  if (packageRoot != null && packageName != null) {
    await _runValidation(packageRoot: packageRoot, packageName: packageName);
    return;
  }
  // coverage:ignore-start
  await build(args, (input, output) async {
    await _runValidation(
      packageRoot: Directory.fromUri(input.packageRoot).path,
      packageName: input.packageName,
    );
  });
  // coverage:ignore-end
}

/// Core validation logic. Analyzes the package, reports results to [stderr],
/// writes the PlantUML diagram, and throws [BuildError] on violations.
Future<void> _runValidation({
  required String packageRoot,
  required String packageName,
  @visibleForTesting StringSink? sink,
}) async {
  final out = sink ?? stderr
    ..writeln()
    ..writeln('[good_intentions] Validating architecture...');

  final report = await analyzeArchitecture(
    packageRoot: packageRoot,
    packageName: packageName,
  );

  reportResults(report, out);

  // Write PlantUML diagram.
  final pumlFile = File(p.join(packageRoot, 'lib', 'architecture.g.puml'));
  pumlFile.parent.createSync(recursive: true);
  pumlFile.writeAsStringSync(report.puml);

  if (report.hasErrors) {
    throw BuildError(
      message: '${report.errors.length} architecture violation(s) found.',
    );
  }

  out.writeln('[good_intentions] Architecture OK.');
}

/// Analyzes the architecture of the package at [packageRoot].
///
/// Returns an [ArchitectureReport] containing all discovered classes,
/// validation results, and a PlantUML diagram.
Future<ArchitectureReport> analyzeArchitecture({
  required String packageRoot,
  String? packageName,
}) async {
  final name =
      packageName ?? _readPackageName(packageRoot);
  final (classes, untagged) = await ClassCollector.collect(packageRoot);
  final graph = DependencyGraph(classes);
  final results = ValidationReporter.validateAll(graph);
  final puml = PumlWriter.write(
    graph,
    name,
    validationResults: results,
  );

  return ArchitectureReport(
    classes: classes,
    untagged: untagged,
    graph: graph,
    results: results,
    puml: puml,
  );
}

/// Writes validation results and untagged warnings to [sink].
void reportResults(ArchitectureReport report, StringSink sink) {
  for (final name in report.untagged) {
    sink.writeln('[!] $name has no intention annotation.');
  }
  for (final r in report.results) {
    switch (r.severity) {
      case Severity.error:
        sink.writeln('[ERROR] ${r.message}');
      case Severity.warning:
        sink.writeln('[WARN] ${r.message}');
      case Severity.info:
        sink.writeln('[INFO] ${r.message}');
      case Severity.ok:
        break;
    }
  }
}

/// Reads the package name from the `pubspec.yaml` at [packageRoot].
String _readPackageName(String packageRoot) {
  final pubspec =
      File(p.join(packageRoot, 'pubspec.yaml')).readAsStringSync();
  final match =
      RegExp(r'^name:\s*(\S+)', multiLine: true).firstMatch(pubspec);
  if (match == null) {
    throw StateError(
      'Could not determine package name from '
      '${p.join(packageRoot, 'pubspec.yaml')}',
    );
  }
  return match.group(1)!;
}
