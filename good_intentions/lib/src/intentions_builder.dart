import 'package:build/build.dart';
import 'package:good_intentions/src/class_collector.dart';
import 'package:good_intentions/src/puml_writer.dart';
import 'package:good_intentions/src/validation_reporter.dart';
import 'package:intentions/intentions.dart' as annotations;
import 'package:intentions_engine/intentions_engine.dart';

/// Aggregate builder that generates a PlantUML architecture diagram
/// and validates architectural dependencies for the entire package.
@annotations.dataSource
class IntentionsBuilder implements Builder {
  @override
  Map<String, List<String>> get buildExtensions => const {
    r'$package$': ['lib/architecture.g.puml'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final packageName = buildStep.inputId.package;

    // 1. Collect all annotated classes.
    final (classes, untagged) = await ClassCollector.collect(buildStep);

    // 2. Build dependency graph + run validation.
    final graph = DependencyGraph(classes);
    final results = ValidationReporter.validateAll(graph);
    ValidationReporter.report(results, log);

    // 3. Warn about untagged concrete classes.
    for (final name in untagged) {
      log.warning(
        '$name is a public concrete class with no intention annotation.',
      );
    }

    // 4. Generate PlantUML diagram.
    final puml = PumlWriter.write(
      graph,
      packageName,
      validationResults: results,
    );
    final outputId = AssetId(packageName, 'lib/architecture.g.puml');
    await buildStep.writeAsString(outputId, puml);
  }
}

/// Factory function for `build.yaml` registration.
Builder intentionsBuilder(BuilderOptions options) => IntentionsBuilder();
