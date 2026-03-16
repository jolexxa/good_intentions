import 'package:intentions/intentions.dart' as annotations;

/// Architectural layers, ordered from highest (presentation) to lowest (data).
///
/// Layer ordering determines the direction of allowed dependencies:
/// higher layers may depend on lower layers, never the reverse.
@annotations.model
enum Layer implements Comparable<Layer> {
  /// UI / presentation.
  view,

  /// View models, cubits, blocs — presentation logic.
  viewModel,

  /// Business orchestration across domain services.
  useCase,

  /// Repositories, domain services.
  domain,

  /// Data sources, API clients, file I/O.
  data;

  /// Whether this layer is above [other] in the architecture.
  bool isAbove(Layer other) => index < other.index;

  /// Whether this layer is below [other] in the architecture.
  bool isBelow(Layer other) => index > other.index;

  @override
  int compareTo(Layer other) => index.compareTo(other.index);
}
