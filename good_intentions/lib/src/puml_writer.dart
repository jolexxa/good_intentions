import 'package:intentions/intentions.dart' as annotations;
import 'package:intentions_engine/intentions_engine.dart';

/// Generates a PlantUML class diagram from a [DependencyGraph].
@annotations.model
abstract final class PumlWriter {
  /// Writes a PlantUML diagram for the given [graph] under [packageName].
  ///
  /// When [validationResults] are provided, error-severity edges are drawn
  /// in red. Results are keyed by (from, to) class names.
  static String write(
    DependencyGraph graph,
    String packageName, {
    List<ValidationResult> validationResults = const [],
  }) {
    final errorEdges = <(String, String)>{
      for (final r in validationResults)
        if (r.severity == Severity.error) (r.from, r.to),
    };
    // Determine which non-model classes have at least one connection
    // (incoming or outgoing). Models are cross-cutting noise and are
    // omitted entirely.
    final connected = <String>{};
    for (final ac in graph.classes) {
      if (ac.intention.isModel) continue;
      for (final depName in ac.dependencies) {
        final dep = graph[depName];
        if (dep == null || dep.intention.isModel) continue;
        connected
          ..add(ac.name)
          ..add(depName);
      }
    }

    // Build owner → parts map for @PartOf nesting.
    final parts = <String, List<AnnotatedClass>>{};
    final owned = <String>{};
    for (final ac in graph.classes) {
      if (!connected.contains(ac.name)) continue;
      if (ac.owner != null && ac.intention.isPartOf) {
        final root = _resolveRootOwner(ac, graph);
        (parts[root] ??= []).add(ac);
        owned.add(ac.name);
      }
    }

    final buffer = StringBuffer()
      ..writeln('@startuml')
      ..writeln()
      ..writeln('package "$packageName" {');

    // Write class declarations (only connected non-model classes).
    // Sort by name for deterministic output.
    final sortedClasses = graph.classes.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    for (final ac in sortedClasses) {
      if (!connected.contains(ac.name)) continue;
      if (owned.contains(ac.name)) continue; // emitted inside owner rectangle

      final stereotype = ac.intention.isPartOf
          ? _resolveOwnerIntention(ac, graph)?.name ?? ac.intention.name
          : ac.intention.name;

      final children = parts[ac.name];
      if (children != null) {
        _writePackage(buffer, ac.name, stereotype, children, graph);
      } else {
        buffer.writeln('  class ${ac.name} << $stereotype >>');
      }
    }

    // Emit rectangles whose root owner is not in the graph (orphaned parts).
    final sortedPartKeys = parts.keys.toList()..sort();
    for (final key in sortedPartKeys) {
      if (graph[key] != null) continue; // already handled above
      _writePackage(buffer, key, null, parts[key]!, graph);
    }

    buffer.writeln();

    // Write dependency arrows (skip model targets).
    // Violations are drawn in red. Sorted for deterministic output.
    for (final ac in sortedClasses) {
      if (ac.intention.isModel) continue;
      final sortedDeps = ac.dependencies.toList()..sort();
      for (final depName in sortedDeps) {
        final dep = graph[depName];
        if (dep == null || dep.intention.isModel) continue;

        final arrow = errorEdges.contains((ac.name, dep.name))
            ? '-[#red]->'
            : '-->';
        buffer.writeln('  ${ac.name} $arrow ${dep.name}');
      }
    }

    buffer
      ..writeln('}')
      ..writeln()
      ..writeln('@enduml')
      ..writeln();

    return buffer.toString();
  }

  /// Writes a PlantUML package grouping an owner and its `@PartOf` children,
  /// with composition lines between the owner and each part.
  static void _writePackage(
    StringBuffer buffer,
    String ownerName,
    String? ownerStereotype,
    List<AnnotatedClass> children,
    DependencyGraph graph,
  ) {
    buffer.writeln('  package "$ownerName" as _$ownerName {');
    if (ownerStereotype != null) {
      buffer.writeln('    class $ownerName << $ownerStereotype >>');
    }
    final sortedChildren = children.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    for (final child in sortedChildren) {
      final childStereotype =
          _resolveOwnerIntention(child, graph)?.name ?? child.intention.name;
      buffer.writeln('    class ${child.name} << $childStereotype >>');
      if (ownerStereotype != null) {
        buffer.writeln('    $ownerName +-- ${child.name}');
      }
    }
    buffer.writeln('  }');
  }

  /// Walks the `@partOf` owner chain to find the root owner's class name.
  static String _resolveRootOwner(
    AnnotatedClass ac,
    DependencyGraph graph,
  ) {
    if (ac.owner == null) return ac.name;
    final owner = graph[ac.owner!];
    if (owner == null) return ac.owner!;
    if (owner.intention.isPartOf) return _resolveRootOwner(owner, graph);
    return owner.name;
  }

  /// Walks the `@partOf` owner chain to find the root owner's [Intention].
  static Intention? _resolveOwnerIntention(
    AnnotatedClass ac,
    DependencyGraph graph,
  ) {
    if (ac.owner == null) return null;
    final owner = graph[ac.owner!];
    if (owner == null) return null;
    if (owner.intention.isPartOf) return _resolveOwnerIntention(owner, graph);
    return owner.intention;
  }
}
