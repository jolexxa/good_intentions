import 'package:intentions/intentions.dart' as annotations;
import 'package:intentions_engine/intentions_engine.dart';

/// Runs architectural validation on a [DependencyGraph] and reports results.
@annotations.useCase
class ValidationReporter {
  /// Validates all dependency edges in [graph] and returns the results.
  List<ValidationResult> validateAll(DependencyGraph graph) {
    final results = <ValidationResult>[];

    for (final ac in graph.classes) {
      for (final depName in ac.dependencies) {
        final dep = graph[depName];
        if (dep == null) continue;

        results.add(validate(from: ac, to: dep, graph: graph));
      }
    }

    return results;
  }
}
