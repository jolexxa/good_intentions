import 'package:intentions/intentions.dart' as annotations;
import 'package:intentions_engine/src/layer.dart';

/// All annotation categories recognized by the intentions system.
///
/// Each intention maps to either a [Layer] (participating in enforcement)
/// or `null` (cross-cutting / special).
@annotations.model
enum Intention {
  /// UI component — maps to [Layer.view].
  view(layer: Layer.view),

  /// Presentation logic — maps to [Layer.viewModel].
  viewModel(layer: Layer.viewModel),

  /// Business orchestration — maps to [Layer.useCase].
  useCase(layer: Layer.useCase),

  /// Domain data gateway — maps to [Layer.domain].
  repository(layer: Layer.domain),

  /// External system adapter — maps to [Layer.data].
  dataSource(layer: Layer.data),

  /// Domain entity or value object — cross-cutting, no layer.
  model(),

  /// Unknown role — temporary migration marker, no layer.
  hack(),

  /// Implementation detail of another class — inherits owner's layer.
  partOf();

  const Intention({this.layer});

  /// The architectural layer this intention maps to, or `null` if it is
  /// cross-cutting (e.g. [model]) or unclassified (e.g. [hack]).
  final Layer? layer;

  /// Whether this intention participates in layer enforcement.
  bool get isLayer => layer != null;

  /// Whether this is the [hack] intention (always warns).
  bool get isHack => this == Intention.hack;

  /// Whether this is the [model] intention (cross-cutting).
  bool get isModel => this == Intention.model;

  /// Whether this is the [partOf] intention (implementation detail).
  bool get isPartOf => this == Intention.partOf;

  /// Maps an annotation runtime type name to its [Intention], or `null`.
  static Intention? fromAnnotationName(String name) => _byName[name];

  static final _byName = <String, Intention>{
    'View': Intention.view,
    'ViewModel': Intention.viewModel,
    'UseCase': Intention.useCase,
    'Repository': Intention.repository,
    'DataSource': Intention.dataSource,
    'Model': Intention.model,
    'Hack': Intention.hack,
    'PartOf': Intention.partOf,
  };
}
