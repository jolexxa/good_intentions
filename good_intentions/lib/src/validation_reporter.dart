import 'package:intentions/intentions.dart' as annotations;
import 'package:intentions_engine/intentions_engine.dart';
import 'package:logging/logging.dart';

/// Runs architectural validation on a [DependencyGraph] and reports results.
@annotations.useCase
abstract final class ValidationReporter {
  /// Validates all dependency edges in [graph] and returns the results.
  static List<ValidationResult> validateAll(DependencyGraph graph) {
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

  /// Logs [results] to [log] at the appropriate severity level.
  ///
  /// Returns `true` if any errors were found.
  static bool report(List<ValidationResult> results, Logger log) {
    var hasErrors = false;

    for (final result in results) {
      switch (result.severity) {
        case Severity.ok:
          break;
        case Severity.info:
          log.info(result.message);
        case Severity.warning:
          log.warning(result.message);
        case Severity.error:
          log.severe(result.message);
          hasErrors = true;
      }
    }

    return hasErrors;
  }
}
