// Static shims for testing
// ignore_for_file: prefer_constructors_over_static_methods

import 'dart:io';

import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/file_system/physical_file_system.dart';
import 'package:good_intentions/src/analyzer_adapter.dart';
import 'package:good_intentions/src/class_collector.dart';
import 'package:good_intentions/src/logger.dart';
import 'package:good_intentions/src/package_file_resolver.dart';
import 'package:good_intentions/src/puml_writer.dart';
import 'package:good_intentions/src/validation_reporter.dart';
import 'package:hooks/hooks.dart';
import 'package:intentions/intentions.dart' as annotations;
import 'package:intentions_engine/intentions_engine.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Signature matching the [build] function from `package:hooks`.
typedef BuildRunner =
    Future<void> Function(
      List<String> args,
      Future<void> Function(BuildInput input, BuildOutputBuilder output)
      builder,
    );

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

/// Orchestrates architecture analysis, validation, and diagram generation.
///
/// All dependencies are injected via the constructor for testability.
/// For build hooks, use the static [validate] entry point.
@annotations.useCase
class ArchitectureValidator {
  /// Creates a validator with all required dependencies.
  const ArchitectureValidator({
    required this.resolver,
    required this.collector,
    required this.reporter,
    required this.pumlWriter,
  });

  /// Creates a validator wired with production dependencies.
  factory ArchitectureValidator.withDefaults({
    required ResourceProvider resourceProvider,
  }) {
    final resolver = PackageFileResolver(resourceProvider);
    return ArchitectureValidator(
      resolver: resolver,
      collector: ClassCollector(
        AnalyzerAdapter(resolver, resourceProvider),
        resourceProvider,
      ),
      reporter: ValidationReporter(),
      pumlWriter: PumlWriter(),
    );
  }

  // -- Static shims for testability -----------------------------------------

  /// Factory for creating an [ArchitectureValidator].
  ///
  /// Defaults to [ArchitectureValidator.withDefaults] with
  /// [PhysicalResourceProvider.INSTANCE]. Swap in tests to return a mock.
  @visibleForTesting
  static ArchitectureValidator Function() createValidator =
      defaultCreateValidator;

  /// Production factory for [createValidator].
  ///
  /// Exposed so tests can restore the default in tearDown.
  static ArchitectureValidator defaultCreateValidator() =>
      ArchitectureValidator.withDefaults(
        resourceProvider: PhysicalResourceProvider.INSTANCE,
      );

  /// The build runner used by [validate].
  ///
  /// Defaults to [build] from `package:hooks`. Swap in tests to
  /// call the callback with a constructed [BuildInput].
  @visibleForTesting
  static BuildRunner buildRunner = build;

  /// The default [buildRunner] value.
  ///
  /// Exposed so tests can restore the default in tearDown.
  static const BuildRunner defaultBuildRunner = build;

  // -- Instance fields ------------------------------------------------------

  /// The resolver for reading package names and tracking files.
  final PackageFileResolver resolver;

  /// The class collector for discovering annotated classes.
  final ClassCollector collector;

  /// The validation reporter for checking dependency rules.
  final ValidationReporter reporter;

  /// The PlantUML writer for generating diagrams.
  final PumlWriter pumlWriter;

  // -- Static entry point ---------------------------------------------------

  /// Validates architecture of the current package from a build hook.
  ///
  /// Usage in `hook/build.dart`:
  ///
  /// ```dart
  /// import 'package:good_intentions/good_intentions.dart';
  ///
  /// Future<void> main(List<String> args) async =>
  ///     ArchitectureValidator.validate(args);
  /// ```
  static Future<void> validate(List<String> args) async {
    await buildRunner(args, (input, output) async {
      final root = Directory.fromUri(input.packageRoot).path;
      final validator = createValidator();

      output.dependencies.addAll(validator.resolver.trackedFiles(root));

      await validator.validatePackage(
        packageRoot: root,
        packageName: input.packageName,
        logger: Logger(stderr),
      );
    });
  }

  // -- Instance methods -----------------------------------------------------

  /// Analyzes the architecture of the package at [packageRoot].
  ///
  /// Returns an [ArchitectureReport] containing all discovered classes,
  /// validation results, and a PlantUML diagram.
  Future<ArchitectureReport> analyze({
    required String packageRoot,
    String? packageName,
  }) async {
    final name = packageName ?? resolver.readPackageName(packageRoot);
    final collection = await collector.collect(packageRoot);
    final graph = DependencyGraph(collection.classes);
    final results = reporter.validateAll(graph);
    final puml = pumlWriter.write(
      graph,
      name,
      validationResults: results,
    );

    return ArchitectureReport(
      classes: collection.classes,
      untagged: collection.untagged,
      graph: graph,
      results: results,
      puml: puml,
    );
  }

  /// Runs full validation: analyzes, reports results, writes the PlantUML
  /// diagram, and throws [BuildError] on violations.
  Future<void> validatePackage({
    required String packageRoot,
    required String packageName,
    required Logger logger,
  }) async {
    logger
      ..info('')
      ..info('Validating architecture...');

    final report = await analyze(
      packageRoot: packageRoot,
      packageName: packageName,
    );

    reportResults(report, logger);

    // Write PlantUML diagram.
    final pumlPath = p.join(packageRoot, 'lib', 'architecture.g.puml');
    final pumlFile = resolver.resourceProvider.getFile(pumlPath);
    pumlFile.parent.create();
    pumlFile.writeAsStringSync(report.puml);

    if (report.hasErrors) {
      throw BuildError(
        message: '${report.errors.length} architecture violation(s) found.',
      );
    }

    logger.info('Architecture OK.');
  }
}

/// Writes validation results and untagged warnings to [logger].
void reportResults(ArchitectureReport report, Logger logger) {
  for (final name in report.untagged) {
    logger.warn('$name has no intention annotation.');
  }
  for (final r in report.results) {
    switch (r.severity) {
      case Severity.error:
        logger.error(r.message);
      case Severity.warning:
        logger.warn(r.message);
      case Severity.info:
        logger.info(r.message);
      case Severity.ok:
        break;
    }
  }
}
