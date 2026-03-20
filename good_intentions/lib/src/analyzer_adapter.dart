import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/file_system/file_system.dart';
// The public API doesn't expose `byteStore`, so we use the internal impl.
// ignore: implementation_imports
import 'package:analyzer/src/dart/analysis/analysis_context_collection.dart';
// FileByteStore shares the analysis server's on-disk cache.
// ignore: implementation_imports
import 'package:analyzer/src/dart/analysis/file_byte_store.dart';
import 'package:good_intentions/src/class_collector.dart';
import 'package:good_intentions/src/package_file_resolver.dart';
import 'package:intentions/intentions.dart' as annotations;
import 'package:intentions_engine/intentions_engine.dart';
import 'package:meta/meta.dart';

/// Intentions package URI prefix.
const String _intentionsPackage = 'package:intentions/';

/// Wraps the Dart analyzer to discover annotated classes in a package.
///
/// Uses a static [createCollection] shim so tests can swap in a mock
/// [AnalysisContextCollection] without running the real analyzer.
@annotations.dataSource
class AnalyzerAdapter {
  /// Creates an adapter that uses [resolver] for package config and
  /// path dependency resolution during Phase 2.
  const AnalyzerAdapter(this.resolver, this.resourceProvider);

  /// The resolver used for reading package config and checking
  /// whether path dependencies use intentions.
  final PackageFileResolver resolver;

  /// File system abstraction passed to the analyzer.
  final ResourceProvider resourceProvider;

  /// Factory for creating the analysis context collection.
  ///
  /// Defaults to [defaultCreateCollection] which uses
  /// [AnalysisContextCollectionImpl] with [FileByteStore] sharing the
  /// analysis server's on-disk cache at `~/.dartServer/.analysis-driver/`.
  ///
  /// Swap in tests to return a mock collection.
  @visibleForTesting
  static AnalysisContextCollection Function({
    required List<String> includedPaths,
    required ResourceProvider resourceProvider,
    String? sdkPath,
  })
  createCollection = defaultCreateCollection;

  /// Production factory for [createCollection].
  ///
  /// Exposed so tests can restore the default in tearDown.
  static AnalysisContextCollection defaultCreateCollection({
    required List<String> includedPaths,
    required ResourceProvider resourceProvider,
    String? sdkPath,
  }) {
    // Use the analyzer's own state location (~/.dartServer/analysis-driver)
    // so we share the analysis server's disk cache. This resolves the home
    // directory via ResourceProvider, which works on all platforms without
    // needing Platform.environment['HOME'].
    final cacheFolder = resourceProvider.getStateLocation('analysis-driver')!;
    return AnalysisContextCollectionImpl(
      includedPaths: includedPaths,
      byteStore: FileByteStore(cacheFolder.path),
      resourceProvider: resourceProvider,
      sdkPath: sdkPath,
    );
  }

  /// Analyzes all `.dart` files reachable from [libDir], walking
  /// transitive imports to discover annotated classes in dependency
  /// packages.
  Future<CollectionResult> analyze(
    String libDir,
    String packageRoot,
  ) async {
    final byName = <String, AnnotatedClass>{};
    final localNames = <String>{};
    final untagged = <String>{};
    final currentPackage = resolver.readPackageName(packageRoot);
    final localLibraries = <LibraryElement>[];

    // Phase 1: Scan local lib/ files.
    final collection = createCollection(
      includedPaths: [libDir],
      resourceProvider: resourceProvider,
    );

    for (final context in collection.contexts) {
      for (final filePath in context.contextRoot.analyzedFiles()) {
        if (!filePath.endsWith('.dart')) continue;

        final unitResult = await context.currentSession.getResolvedUnit(
          filePath,
        );
        if (unitResult is! ResolvedUnitResult) continue;
        if (unitResult.isPart) continue;

        final lib = unitResult.libraryElement;
        localLibraries.add(lib);

        _collectFromLibrary(
          lib,
          byName,
          localNames: localNames,
          untagged: untagged,
        );
      }
    }

    // Phase 2: Walk transitive imports for local path dependency classes.
    final visited = <Uri>{};
    final queue = [...localLibraries];
    final pathDepCache = <String, bool>{};
    final packageConfig = resolver.readPackageConfig(packageRoot);

    while (queue.isNotEmpty) {
      final lib = queue.removeLast();
      if (!visited.add(lib.uri)) continue;

      queue
        ..addAll(lib.firstFragment.importedLibraries)
        ..addAll(lib.exportedLibraries);

      final uri = lib.uri.toString();
      if (!uri.startsWith('package:')) continue;
      if (uri.startsWith('package:$currentPackage/')) continue;

      final pkgName = uri.substring('package:'.length).split('/').first;
      if (!resolver.isIntentionsPathDep(
        pkgName,
        packageConfig,
        pathDepCache,
      )) {
        continue;
      }

      _collectFromLibrary(
        lib,
        byName,
        external: true,
        localNames: localNames,
        untagged: untagged,
      );
    }

    // Release analysis driver resources. LibraryElement objects are
    // backed by the driver's linked element factory, so we must wait
    // until after Phase 2's import graph walk to dispose.
    await collection.dispose();

    return CollectionResult(
      classes: byName.values.toList(),
      untagged: untagged.toList()..sort(),
    );
  }

  // -- Extraction helpers ---------------------------------------------------

  static void _collectFromLibrary(
    LibraryElement library,
    Map<String, AnnotatedClass> byName, {
    bool external = false,
    Set<String>? localNames,
    Set<String>? untagged,
  }) {
    for (final classElem in library.classes) {
      if (classElem.isPrivate) continue;

      final name = classElem.name;
      if (name == null) continue;

      final info = _annotationOf(classElem);
      if (info == null) {
        if (!classElem.isAbstract && !classElem.isInterface) {
          untagged?.add(name);
        }
        continue;
      }

      final extracted = _extractDependencies(classElem);
      final annotated = AnnotatedClass(
        name: name,
        intention: info.intention,
        dependencies: extracted.dependencies,
        owner: info.owner,
      );

      if (external) {
        if (localNames?.contains(name) ?? false) continue;
        byName[name] = annotated;
      } else {
        localNames?.add(name);
        byName[name] = annotated;
      }

      for (final ext in extracted.externalClasses) {
        if (localNames?.contains(ext.name) ?? false) continue;
        byName.putIfAbsent(ext.name, () => ext);
      }
    }
  }

  static AnnotationInfo? _annotationOf(ClassElement element) {
    Intention? primary;
    String? owner;

    for (final annotation in element.metadata.annotations) {
      final constantValue = annotation.computeConstantValue();
      final annotationType = constantValue?.type;
      if (annotationType is! InterfaceType) continue;

      final typeElement = annotationType.element;
      if (!_isFromIntentionsPackage(typeElement)) continue;

      final typeName = typeElement.name;
      if (typeName == null) continue;

      final intention = Intention.fromAnnotationName(typeName);
      if (intention == null) continue;

      if (intention.isPartOf) {
        final ownerType = constantValue!.getField('owner')?.toTypeValue();
        if (ownerType is InterfaceType) {
          owner = ownerType.element.name;
        }
      } else {
        primary ??= intention;
      }
    }

    if (primary != null) {
      return AnnotationInfo(intention: primary, owner: owner);
    }
    if (owner != null) {
      return AnnotationInfo(intention: Intention.partOf, owner: owner);
    }
    return null;
  }

  static bool _isFromIntentionsPackage(InterfaceElement element) {
    return element.library.uri.toString().startsWith(_intentionsPackage);
  }

  static void _collectInterfaceTypes(
    DartType type,
    Set<InterfaceElement> result,
  ) {
    if (type is InterfaceType) {
      result.add(type.element);
      for (final typeArg in type.typeArguments) {
        _collectInterfaceTypes(typeArg, result);
      }
    }
  }

  static void _processElements(
    Set<InterfaceElement> elements,
    Set<String> deps,
    List<AnnotatedClass> external,
  ) {
    for (final element in elements) {
      final name = element.name;
      if (name == null) continue;
      deps.add(name);

      if (element is ClassElement) {
        final info = _annotationOf(element);
        if (info != null) {
          external.add(
            AnnotatedClass(
              name: name,
              intention: info.intention,
              dependencies: const {},
              owner: info.owner,
            ),
          );
        }
      }
    }
  }

  static DependencyExtractionResult _extractDependencies(
    ClassElement element,
  ) {
    final deps = <String>{};
    final external = <AnnotatedClass>[];
    final elements = <InterfaceElement>{};

    for (final constructor in element.constructors) {
      for (final param in constructor.formalParameters) {
        _collectInterfaceTypes(param.type, elements);
      }
    }

    for (final field in element.fields) {
      if (field.isStatic) continue;
      _collectInterfaceTypes(field.type, elements);
    }

    _processElements(elements, deps, external);

    return DependencyExtractionResult(
      dependencies: deps,
      externalClasses: external,
    );
  }
}
