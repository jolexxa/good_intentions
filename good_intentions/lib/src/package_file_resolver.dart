import 'dart:convert';

import 'package:analyzer/file_system/file_system.dart';
import 'package:intentions/intentions.dart' as annotations;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;

/// Resolves package files and tracked file paths for build hook dependencies.
///
/// Accepts a [ResourceProvider] so tests can inject a
/// `MemoryResourceProvider` instead of touching the real filesystem.
@annotations.dataSource
class PackageFileResolver {
  /// Creates a resolver backed by [resourceProvider].
  const PackageFileResolver(this.resourceProvider);

  /// The file system abstraction used for all file operations.
  final ResourceProvider resourceProvider;

  /// Hosted packages live in `.pub-cache` — we skip them during dependency
  /// tracking since we only enforce intentions on the user's own code.
  @visibleForTesting
  static const pubCacheSegment = '.pub-cache';

  /// Pattern matching `intentions:` as a dependency key in a pubspec.
  static final _intentionsDep = RegExp(r'^\s+intentions:', multiLine: true);

  /// Returns the [Uri]s of all files that contribute to the fingerprint.
  ///
  /// Used to declare build hook dependencies via
  /// `output.dependencies.addAll(...)` so the build system knows when to
  /// re-run the hook.
  List<Uri> trackedFiles(String packageRoot) =>
      _trackedFilePaths(packageRoot).map(p.toUri).toList();

  /// Single source of truth for which file paths matter.
  ///
  /// Tracked files (sorted by path for determinism):
  ///   1. All `.dart` files in `packageRoot/lib/`
  ///   2. `pubspec.lock` (hosted dependency versions)
  ///   3. `pubspec.yaml` of every path dependency (detects when
  ///      `intentions` is added or removed)
  ///   4. All `.dart` files in `lib/` of path deps that use `intentions`
  List<String> _trackedFilePaths(String packageRoot) {
    final paths = <String>[];

    // 1. All .dart files in lib/.
    final libFolder = resourceProvider.getFolder(p.join(packageRoot, 'lib'));
    if (libFolder.exists) {
      for (final file in _dartFilesIn(libFolder)) {
        paths.add(file.path);
      }
    }

    // 2. pubspec.lock.
    final lockFile = resourceProvider.getFile(
      p.join(packageRoot, 'pubspec.lock'),
    );
    if (lockFile.exists) {
      paths.add(lockFile.path);
    }

    // 3 & 4. Path dependency pubspecs and their dart sources.
    final packageConfig = readPackageConfig(packageRoot);
    final depCache = <String, bool>{};

    for (final entry in packageConfig.entries) {
      final pkgName = entry.key;
      final rootPath = entry.value;

      if (rootPath.contains(pubCacheSegment)) continue;

      final depPubspec = resourceProvider.getFile(
        p.join(rootPath, 'pubspec.yaml'),
      );
      if (depPubspec.exists) {
        paths.add(depPubspec.path);
      }

      if (isIntentionsPathDep(pkgName, packageConfig, depCache)) {
        final depLib = resourceProvider.getFolder(p.join(rootPath, 'lib'));
        if (depLib.exists) {
          for (final file in _dartFilesIn(depLib)) {
            paths.add(file.path);
          }
        }
      }
    }

    return paths;
  }

  /// Recursively collects all `.dart` files under [folder], sorted by path.
  List<File> _dartFilesIn(Folder folder) {
    final result = <File>[];
    void walk(Folder f) {
      for (final child in f.getChildren()) {
        if (child is File && child.path.endsWith('.dart')) {
          result.add(child);
        } else if (child is Folder) {
          walk(child);
        }
      }
    }

    walk(folder);
    result.sort((a, b) => a.path.compareTo(b.path));
    return result;
  }

  // -- Shared helpers (also used by AnalyzerAdapter) -------------------------

  /// Reads the package name from the `pubspec.yaml` at [packageRoot].
  String readPackageName(String packageRoot) {
    final pubspec = resourceProvider
        .getFile(p.join(packageRoot, 'pubspec.yaml'))
        .readAsStringSync();
    final match = RegExp(
      r'^name:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec);
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
  Map<String, String> readPackageConfig(String packageRoot) {
    final configFile = resourceProvider.getFile(
      p.join(packageRoot, '.dart_tool', 'package_config.json'),
    );
    if (!configFile.exists) return {};

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

  /// Returns `true` if [packageName] is a local path dependency whose
  /// `pubspec.yaml` lists `intentions` as a dependency.
  ///
  /// Hosted packages (paths containing `.pub-cache`) are always skipped —
  /// we only enforce intentions on your own code.
  bool isIntentionsPathDep(
    String packageName,
    Map<String, String> packageConfig,
    Map<String, bool> cache,
  ) {
    if (cache.containsKey(packageName)) return cache[packageName]!;

    bool result;

    final rootPath = packageConfig[packageName];

    // Hosted packages live in .pub-cache. Local path dependencies don't.
    if (rootPath == null || rootPath.contains(pubCacheSegment)) {
      result = false;
    } else {
      final pubspecFile = resourceProvider.getFile(
        p.join(rootPath, 'pubspec.yaml'),
      );
      if (!pubspecFile.exists) {
        result = false;
      } else {
        final content = pubspecFile.readAsStringSync();
        result = _intentionsDep.hasMatch(content);
      }
    }

    cache[packageName] = result;
    return result;
  }
}
