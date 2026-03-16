import 'package:intentions/intentions.dart' as annotations;
import 'package:intentions_engine/src/annotated_class.dart';
import 'package:intentions_engine/src/layer.dart';
import 'package:meta/meta.dart';

/// Resolves the effective [Layer] of [ac], following `@partOf` chains.
///
/// Returns [AnnotatedClass.layer] directly for non-partOf classes.
/// For `@partOf` classes, walks the owner chain in [graph] until a
/// concrete layer is found (or returns `null` if the owner is missing).
@annotations.useCase
Layer? effectiveLayer(AnnotatedClass ac, DependencyGraph graph) {
  if (ac.layer != null) return ac.layer;
  if (ac.owner == null) return null;
  final ownerClass = graph[ac.owner!];
  if (ownerClass == null) return null;
  return effectiveLayer(ownerClass, graph);
}

/// A dependency graph of all annotated classes in a package.
@annotations.model
class DependencyGraph {
  /// Creates a dependency graph from a set of annotated classes.
  DependencyGraph(Iterable<AnnotatedClass> classes)
      : _byName = {for (final c in classes) c.name: c};

  final Map<String, AnnotatedClass> _byName;

  /// All annotated classes in the graph.
  Iterable<AnnotatedClass> get classes => _byName.values;

  /// Looks up a class by name, or returns `null`.
  AnnotatedClass? operator [](String name) => _byName[name];

  /// Returns the set of classes that are "claimed" — i.e., depended on by
  /// at least one class in a higher architectural layer.
  ///
  /// A claimed class can only be accessed through the layer that claims it.
  ///
  /// If [excluding] is provided, that class is excluded from consideration
  /// as a claimer. This is used during validation so that the consumer
  /// being checked does not self-claim its own target.
  Set<ClaimedClass> claimedClasses({AnnotatedClass? excluding}) {
    final claimed = <ClaimedClass>{};

    for (final consumer in _byName.values) {
      if (excluding != null && consumer == excluding) continue;

      final consumerLayer = effectiveLayer(consumer, this);
      if (consumerLayer == null) continue;

      for (final depName in consumer.dependencies) {
        final dep = _byName[depName];
        if (dep == null) continue;

        final depLayer = effectiveLayer(dep, this);
        if (depLayer == null) continue;

        // A class is claimed when a higher layer depends on it.
        if (consumerLayer.isAbove(depLayer)) {
          final existing = claimed.lookup(ClaimedClass(dep, consumerLayer));
          if (existing != null) {
            // Keep the highest claiming layer.
            if (consumerLayer.isAbove(existing.claimedByLayer)) {
              claimed
                ..remove(existing)
                ..add(ClaimedClass(dep, consumerLayer));
            }
          } else {
            claimed.add(ClaimedClass(dep, consumerLayer));
          }
        }
      }
    }

    return claimed;
  }
}

/// A class that has been claimed by a higher architectural layer.
@immutable
@annotations.model
class ClaimedClass {
  /// Creates a claimed class reference.
  const ClaimedClass(this.annotatedClass, this.claimedByLayer);

  /// The claimed class.
  final AnnotatedClass annotatedClass;

  /// The highest layer that claims this class (depends on it).
  final Layer claimedByLayer;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ClaimedClass &&
          runtimeType == other.runtimeType &&
          annotatedClass == other.annotatedClass;

  @override
  int get hashCode => annotatedClass.hashCode;

  @override
  String toString() =>
      'ClaimedClass(${annotatedClass.name}, by ${claimedByLayer.name})';
}
