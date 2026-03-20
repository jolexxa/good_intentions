import 'package:analyzer/file_system/file_system.dart';
import 'package:good_intentions/src/analyzer_adapter.dart';
import 'package:intentions/intentions.dart' as annotations;
import 'package:intentions_engine/intentions_engine.dart';
import 'package:path/path.dart' as p;

/// The result of extracting an intention annotation from a class element.
@annotations.model
class AnnotationInfo {
  /// Creates an annotation info.
  const AnnotationInfo({required this.intention, this.owner});

  /// The architectural intention declared on the class.
  final Intention intention;

  /// The owner class name, if this is a `@PartOf` annotation.
  final String? owner;
}

/// The result of collecting annotated classes from a package.
@annotations.model
class CollectionResult {
  /// Creates a collection result.
  const CollectionResult({required this.classes, required this.untagged});

  /// All annotated classes discovered in the package and its dependencies.
  final List<AnnotatedClass> classes;

  /// Public, concrete class names with no intention annotation.
  final List<String> untagged;
}

/// The result of extracting dependencies from a class element.
@annotations.model
class DependencyExtractionResult {
  /// Creates a dependency extraction result.
  const DependencyExtractionResult({
    required this.dependencies,
    required this.externalClasses,
  });

  /// Dependency names referenced by the class.
  final Set<String> dependencies;

  /// Externally-annotated classes discovered during extraction.
  final List<AnnotatedClass> externalClasses;
}

/// Collects all annotated classes from a package and its dependencies.
///
/// Wraps an [AnalyzerAdapter] to discover annotated classes by running
/// the Dart analyzer.
@annotations.dataSource
class ClassCollector {
  /// Creates a collector using [analyzer] for running the Dart analyzer.
  ///
  /// [resourceProvider] is used to check whether the `lib/` directory exists.
  const ClassCollector(this.analyzer, this.resourceProvider);

  /// The analyzer adapter that performs the actual analysis.
  final AnalyzerAdapter analyzer;

  /// File system abstraction for checking directory existence.
  final ResourceProvider resourceProvider;

  /// Scans all `.dart` files in `lib/` and walks transitive imports to
  /// discover annotated classes in dependency packages.
  ///
  /// [packageRoot] is the absolute path to the package directory (must
  /// contain `pubspec.yaml` and `.dart_tool/package_config.json`).
  Future<CollectionResult> collect(String packageRoot) async {
    final libDir = p.join(packageRoot, 'lib');
    if (!resourceProvider.getFolder(libDir).exists) {
      return const CollectionResult(
        classes: <AnnotatedClass>[],
        untagged: <String>[],
      );
    }

    return analyzer.analyze(libDir, packageRoot);
  }
}
