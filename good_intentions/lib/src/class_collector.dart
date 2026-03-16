import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:intentions/intentions.dart' as annotations;
import 'package:intentions_engine/intentions_engine.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Intentions package.
const String intentionsPackage = 'package:intentions/';

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

/// Collects all annotated classes from a package and its dependencies.
@annotations.dataSource
abstract final class ClassCollector {
  /// Override in tests to bypass the analyzer. Reset to `null` in tearDown.
  @visibleForTesting
  static Future<(List<AnnotatedClass>, List<String>)> Function(String)?
      collectOverride;

  /// Scans all `.dart` files in `lib/` (Phase 1) and then walks transitive
  /// imports to discover annotated classes in dependency packages (Phase 2).
  ///
  /// [packageRoot] is the absolute path to the package directory (must contain
  /// `pubspec.yaml` and `.dart_tool/package_config.json`).
  ///
  /// Local definitions always take priority over external discoveries.
  ///
  /// Returns a record of (annotated classes, untagged concrete class names).
  /// Untagged classes are public, non-abstract, non-interface classes that
  /// have no intention annotation.
  static Future<(List<AnnotatedClass>, List<String>)> collect(
    String packageRoot,
  ) async {
    if (collectOverride != null) return collectOverride!(packageRoot);

    final byName = <String, AnnotatedClass>{};
    final localNames = <String>{};
    final untagged = <String>{};
    final currentPackage = _readPackageName(packageRoot);
    final localLibraries = <LibraryElement>[];

    final libDir = p.join(packageRoot, 'lib');
    if (!Directory(libDir).existsSync()) {
      return (<AnnotatedClass>[], <String>[]);
    }

    // Phase 1: Scan local lib/ files.
    final collection = AnalysisContextCollection(
      includedPaths: [libDir],
    );

    for (final context in collection.contexts) {
      for (final filePath in context.contextRoot.analyzedFiles()) {
        if (!filePath.endsWith('.dart')) continue;

        final unitResult =
            await context.currentSession.getResolvedUnit(filePath);
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
    final packageConfig = _readPackageConfig(packageRoot);

    while (queue.isNotEmpty) {
      final lib = queue.removeLast();
      if (!visited.add(lib.uri)) continue;

      // Always queue imports and exports so we walk the full transitive graph.
      queue
        ..addAll(lib.firstFragment.importedLibraries)
        ..addAll(lib.exportedLibraries);

      final uri = lib.uri.toString();
      // Skip dart: SDK libraries and the current package's own libraries.
      if (!uri.startsWith('package:')) continue;
      if (uri.startsWith('package:$currentPackage/')) continue;

      // Only collect from local path dependencies that use intentions.
      final pkgName = uri.substring('package:'.length).split('/').first;
      if (!_isIntentionsPathDep(pkgName, packageConfig, pathDepCache)) {
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

    return (byName.values.toList(), untagged.toList()..sort());
  }

  /// Reads the package name from the `pubspec.yaml` at [packageRoot].
  static String _readPackageName(String packageRoot) {
    final pubspec =
        File(p.join(packageRoot, 'pubspec.yaml')).readAsStringSync();
    final match =
        RegExp(r'^name:\s*(\S+)', multiLine: true).firstMatch(pubspec);
    if (match == null) {
      throw StateError(
        'Could not determine package name from '
        '${p.join(packageRoot, 'pubspec.yaml')}',
      );
    }
    return match.group(1)!;
  }

  /// Reads `.dart_tool/package_config.json` and returns a map of
  /// package name → resolved root path.
  static Map<String, String> _readPackageConfig(String packageRoot) {
    final configFile = File(
      p.join(packageRoot, '.dart_tool', 'package_config.json'),
    );
    if (!configFile.existsSync()) return {};

    final json =
        jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
    final packages = json['packages'] as List<dynamic>;
    final result = <String, String>{};
    final configDir = p.join(packageRoot, '.dart_tool');

    for (final pkg in packages) {
      final map = pkg as Map<String, dynamic>;
      final name = map['name'] as String;
      final rootUri = map['rootUri'] as String;

      // Resolve rootUri relative to the package_config.json directory.
      final resolvedRoot = rootUri.startsWith('file://')
          ? Uri.parse(rootUri).toFilePath()
          : p.normalize(p.join(configDir, rootUri));

      result[name] = resolvedRoot;
    }

    return result;
  }

  /// Pattern matching `intentions:` as a dependency key in a pubspec.
  static final _intentionsDep = RegExp(r'^\s+intentions:', multiLine: true);

  /// Returns `true` if [packageName] is a local path dependency whose
  /// `pubspec.yaml` lists `intentions` as a dependency.
  ///
  /// Hosted packages (paths containing `.pub-cache`) are always skipped —
  /// we only enforce intentions on your own code.
  static bool _isIntentionsPathDep(
    String packageName,
    Map<String, String> packageConfig,
    Map<String, bool> cache,
  ) {
    if (cache.containsKey(packageName)) return cache[packageName]!;

    bool result;

    final rootPath = packageConfig[packageName];

    // Hosted packages live in .pub-cache. Local path dependencies don't.
    if (rootPath == null || rootPath.contains('.pub-cache')) {
      result = false;
    } else {
      final pubspecFile = File(p.join(rootPath, 'pubspec.yaml'));
      if (!pubspecFile.existsSync()) {
        result = false;
      } else {
        final content = pubspecFile.readAsStringSync();
        result = _intentionsDep.hasMatch(content);
      }
    }

    cache[packageName] = result;
    return result;
  }

  /// Extracts annotated classes from a single [library] into [byName].
  ///
  /// When [external] is `true`, only preserves entries whose names appear in
  /// [localNames] (true local definitions from Phase 1). External stubs
  /// added by [_processElements] during Phase 1 can be overwritten by
  /// Phase 2's full-dependency versions.
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
        // Track untagged concrete classes. The caller controls whether
        // warnings are collected by passing or omitting [untagged].
        if (!classElem.isAbstract && !classElem.isInterface) {
          untagged?.add(name);
        }
        continue;
      }

      final (deps, externalClasses) = _extractDependencies(classElem);
      final annotated = AnnotatedClass(
        name: name,
        intention: info.intention,
        dependencies: deps,
        owner: info.owner,
      );

      if (external) {
        // Only protect true local definitions; overwrite Phase 1 stubs.
        if (localNames?.contains(name) ?? false) continue;
        byName[name] = annotated;
      } else {
        localNames?.add(name);
        byName[name] = annotated;
      }

      for (final ext in externalClasses) {
        if (localNames?.contains(ext.name) ?? false) continue;
        byName.putIfAbsent(ext.name, () => ext);
      }
    }
  }

  /// Extracts the [AnnotationInfo] from [element]'s annotations, or `null`.
  ///
  /// Scans all annotations to support dual annotations (e.g.,
  /// `@model @PartOf(X)`). The primary layer/model/hack annotation governs
  /// intention; `@PartOf` provides the owner. If only `@PartOf` is present,
  /// `Intention.partOf` is used as the fallback intention.
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

  /// Returns whether [element] is declared in `package:intentions`.
  static bool _isFromIntentionsPackage(InterfaceElement element) {
    return element.library.uri.toString().startsWith(intentionsPackage);
  }

  /// Recursively collects all [InterfaceElement]s from a type, including
  /// generic type arguments (e.g., `Map<String, CowModelConfig>` yields
  /// both `Map`, `String`, and `CowModelConfig`).
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

  /// Processes a set of discovered [InterfaceElement]s, adding their names
  /// to [deps] and any externally-annotated ones to [external].
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

  /// Extracts dependency names and any externally-annotated classes from
  /// [element]'s constructor parameters and instance fields.
  static (Set<String>, List<AnnotatedClass>) _extractDependencies(
    ClassElement element,
  ) {
    final deps = <String>{};
    final external = <AnnotatedClass>[];
    final elements = <InterfaceElement>{};

    // Constructor parameters (with recursive generic type extraction).
    for (final constructor in element.constructors) {
      for (final param in constructor.formalParameters) {
        _collectInterfaceTypes(param.type, elements);
      }
    }

    // Instance fields (with recursive generic type extraction).
    for (final field in element.fields) {
      if (field.isStatic) continue;
      _collectInterfaceTypes(field.type, elements);
    }

    _processElements(elements, deps, external);

    return (deps, external);
  }
}
