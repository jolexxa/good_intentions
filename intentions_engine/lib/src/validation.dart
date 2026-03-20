import 'package:intentions/intentions.dart' as annotations;
import 'package:intentions_engine/src/annotated_class.dart';
import 'package:intentions_engine/src/dependency_graph.dart';
import 'package:intentions_engine/src/layer.dart';

/// The severity of a validation result.
@annotations.model
enum Severity {
  /// Dependency is valid.
  ok,

  /// Dependency skips a layer but no intermediate class wraps the target yet.
  info,

  /// Dependency is allowed but skips an architectural layer.
  warning,

  /// Dependency violates architectural rules.
  error,
}

/// The result of validating a dependency between two annotated classes.
@annotations.model
class ValidationResult {
  /// Creates a validation result.
  const ValidationResult({
    required this.severity,
    required this.message,
    this.from = '',
    this.to = '',
  });

  /// The class name of the dependency source.
  final String from;

  /// The class name of the dependency target.
  final String to;

  /// The severity of this result.
  final Severity severity;

  /// A human-readable description of the validation outcome.
  final String message;

  @override
  String toString() => 'ValidationResult(${severity.name}: $message)';
}

/// Validates a dependency from [from] to [to] within the given [graph].
///
/// Returns a [ValidationResult] describing whether the dependency is
/// allowed, warned, or forbidden.
@annotations.useCase
ValidationResult validate({
  required AnnotatedClass from,
  required AnnotatedClass to,
  required DependencyGraph graph,
}) {
  ValidationResult result({
    required Severity severity,
    required String message,
  }) => ValidationResult(
    from: from.name,
    to: to.name,
    severity: severity,
    message: message,
  );

  // Model is cross-cutting — always ok.
  if (to.intention.isModel) {
    return result(
      severity: Severity.ok,
      message: 'Models are cross-cutting and can be referenced by any layer.',
    );
  }

  // Hack source — always warn.
  if (from.intention.isHack) {
    return result(
      severity: Severity.warning,
      message:
          '${from.name} is annotated @hack — '
          'all dependencies produce warnings until its role is determined.',
    );
  }

  // Hack target — always warn.
  if (to.intention.isHack) {
    return result(
      severity: Severity.warning,
      message:
          '${to.name} is annotated @hack — '
          'depending on it produces a warning until its role is determined.',
    );
  }

  // Pure @partOf target — only the owner and siblings may depend on it.
  if (to.intention.isPartOf && to.owner != null) {
    final isOwner = from.name == to.owner;
    final isSibling = from.owner != null && from.owner == to.owner;
    if (!isOwner && !isSibling) {
      return result(
        severity: Severity.error,
        message:
            '${to.name} is an implementation detail of ${to.owner} — '
            '${from.name} cannot depend on it directly.',
      );
    }
  }

  final fromLayer = effectiveLayer(from, graph);
  final toLayer = effectiveLayer(to, graph);

  // If either class is non-layer (model/hack already handled), allow it.
  if (fromLayer == null || toLayer == null) {
    return result(
      severity: Severity.ok,
      message: 'Non-layer annotations are not subject to layer enforcement.',
    );
  }

  // Upward dependency — always an error.
  if (fromLayer.isBelow(toLayer)) {
    return result(
      severity: Severity.error,
      message:
          '${from.name} (${fromLayer.name}) cannot depend on '
          '${to.name} (${toLayer.name}) — upward dependencies are forbidden.',
    );
  }

  // Same-layer dependency — error unless owner or @partOf sibling.
  if (fromLayer == toLayer) {
    if (to.owner != null && to.owner == from.name) {
      return result(
        severity: Severity.ok,
        message: 'Owner accessing its own implementation detail.',
      );
    }
    if (from.owner != null && from.owner == to.owner) {
      return result(
        severity: Severity.ok,
        message: '@PartOf siblings of the same owner can access each other.',
      );
    }

    return result(
      severity: Severity.error,
      message:
          '${from.name} and ${to.name} are both at the '
          '${fromLayer.name} layer — sibling dependencies are forbidden.',
    );
  }

  // Downward dependency — check if target is claimed by someone else.
  // Exclude `from` so it doesn't self-claim its own target.
  final claimed = graph.claimedClasses(excluding: from);
  final claim = claimed.lookup(ClaimedClass(to, toLayer));

  if (claim != null) {
    // The claiming layer itself may access the target directly.
    if (fromLayer == claim.claimedByLayer) {
      return result(
        severity: Severity.ok,
        message:
            '${to.name} is claimed by ${claim.claimedByLayer.name}, '
            'and ${from.name} is at that layer.',
      );
    }

    // Everyone else — above or below — must go through the claiming layer.
    return result(
      severity: Severity.error,
      message:
          '${to.name} is claimed by the ${claim.claimedByLayer.name} '
          'layer — ${from.name} (${fromLayer.name}) must access it through '
          'that layer, not directly.',
    );
  }

  // Downward but skipping layers — the claiming check above already
  // enforces access through intermediate wrappers (as errors). This check
  // reports an info when no intermediate class wraps the target yet,
  // highlighting gaps in coverage.
  final distance = toLayer.index - fromLayer.index;
  if (distance > 1) {
    final skipped = Layer.values
        .where((l) => l.index > fromLayer.index && l.index < toLayer.index)
        .map((l) => l.name)
        .join(', ');
    return result(
      severity: Severity.warning,
      message:
          '${from.name} (${fromLayer.name}) depends on '
          '${to.name} (${toLayer.name}) — skipping $skipped '
          '(no intermediate class wraps ${to.name} yet).',
    );
  }

  // Direct neighbor — ok.
  return result(
    severity: Severity.ok,
    message: 'Valid downward dependency to adjacent layer.',
  );
}
