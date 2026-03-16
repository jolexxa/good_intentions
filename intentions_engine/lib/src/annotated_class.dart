import 'package:intentions/intentions.dart' as annotations;
import 'package:intentions_engine/src/intention.dart';
import 'package:intentions_engine/src/layer.dart';
import 'package:meta/meta.dart';

/// A class declaration paired with its architectural [intention].
@immutable
@annotations.model
class AnnotatedClass {
  /// Creates an annotated class reference.
  const AnnotatedClass({
    required this.name,
    required this.intention,
    required this.dependencies,
    this.owner,
  });

  /// The class name.
  final String name;

  /// The architectural intention declared on the class.
  final Intention intention;

  /// Names of other annotated classes this class depends on
  /// (via constructor parameters, fields, etc.).
  final Set<String> dependencies;

  /// The name of the owning class, if this class is `@PartOf(Owner)`.
  final String? owner;

  /// The architectural layer, or `null` if cross-cutting / unclassified.
  Layer? get layer => intention.layer;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AnnotatedClass &&
          runtimeType == other.runtimeType &&
          name == other.name;

  @override
  int get hashCode => name.hashCode;

  @override
  String toString() => 'AnnotatedClass($name, @${intention.name})';
}
