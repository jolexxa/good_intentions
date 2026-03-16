/// Marks a class as a view — a UI component that renders state and
/// forwards user interactions to a [viewModel].
const view = View();

/// Marks a class as a view model — presentation logic that mediates
/// between [view]s and [useCase]s.
const viewModel = ViewModel();

/// Marks a class as a repository — a domain-level data gateway that
/// owns state for a specific bounded context.
const repository = Repository();

/// Marks a class as a use case — a single unit of business orchestration
/// that coordinates one or more [repository] instances.
const useCase = UseCase();

/// Marks a class as a model — a domain entity or value object.
const model = Model();

/// Marks a class as a data source — a low-level adapter for external
/// systems (APIs, databases, file I/O, etc.).
const dataSource = DataSource();

/// Marks a class whose architectural role is not yet determined.
/// Use during migrations when you're not sure what something is yet.
const hack = Hack();

/// {@template view}
/// Annotation indicating a view layer component.
/// {@endtemplate}
class View {
  /// {@macro view}
  const View();
}

/// {@template view_model}
/// Annotation indicating a view model (presentation logic) component.
/// {@endtemplate}
class ViewModel {
  /// {@macro view_model}
  const ViewModel();
}

/// {@template repository}
/// Annotation indicating a repository (domain data gateway) component.
/// {@endtemplate}
class Repository {
  /// {@macro repository}
  const Repository();
}

/// {@template use_case}
/// Annotation indicating a use case (business orchestration) component.
/// {@endtemplate}
class UseCase {
  /// {@macro use_case}
  const UseCase();
}

/// {@template model}
/// Annotation indicating a domain model (entity or value object).
/// {@endtemplate}
class Model {
  /// {@macro model}
  const Model();
}

/// {@template data_source}
/// Annotation indicating a data source (external system adapter).
/// {@endtemplate}
class DataSource {
  /// {@macro data_source}
  const DataSource();
}

/// {@template hack}
/// Annotation for classes whose architectural role is undetermined.
/// Intended as a temporary marker during migration.
/// {@endtemplate}
class Hack {
  /// {@macro hack}
  const Hack();
}

/// {@template part_of}
/// Marks a class as an implementation detail of [owner].
///
/// The class inherits [owner]'s architectural layer. Only [owner] may
/// depend on this class — all other consumers get an error.
/// {@endtemplate}
class PartOf {
  /// {@macro part_of}
  const PartOf(this.owner);

  /// The class this implementation detail belongs to.
  final Type owner;
}
