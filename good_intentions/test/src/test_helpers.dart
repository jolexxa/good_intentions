import 'dart:io';
import 'dart:isolate';

import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:glob/glob.dart';
import 'package:logging/logging.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;

/// Creates a [TestReaderWriter] pre-populated with all `.dart` library files
/// from the current isolate's package dependencies.
///
/// This allows the analyzer to resolve annotations and types from real
/// packages (like `package:intentions`) when running builder tests.
Future<TestBuilderResult> testBuilderWithDeps(
  Builder builder,
  Map<String, String> sourceAssets, {
  required String rootPackage,
  void Function(LogRecord)? onLog,
}) async {
  final pkgConfig = await loadPackageConfigUri(
    (await Isolate.packageConfig)!,
  );
  final assetReader = PackageAssetReader(pkgConfig, rootPackage);
  final readerWriter = TestReaderWriter(rootPackage: rootPackage);

  // Copy all real package library files and pubspec.yaml into the
  // in-memory store.
  for (final package in pkgConfig.packages) {
    await for (final id in assetReader.findAssets(
      Glob('lib/**.dart'),
      package: package.name,
    )) {
      readerWriter.testing.writeBytes(id, await assetReader.readAsBytes(id));
    }

    // Copy pubspec.yaml so ClassCollector can detect path dependencies.
    // PackageAssetReader can't resolve non-lib assets for non-root packages,
    // so we read directly from the file system using the package root.
    final root = package.root.toFilePath();
    final pubspecFile = File(p.join(root, 'pubspec.yaml'));
    if (pubspecFile.existsSync()) {
      readerWriter.testing.writeBytes(
        AssetId(package.name, 'pubspec.yaml'),
        await pubspecFile.readAsBytes(),
      );
    }
  }

  // Write synthetic test source files.
  for (final entry in sourceAssets.entries) {
    readerWriter.testing.writeString(makeAssetId(entry.key), entry.value);
  }

  return testBuilder(
    builder,
    {},
    rootPackage: rootPackage,
    readerWriter: readerWriter,
    packageConfig: pkgConfig,
    flattenOutput: true,
    onLog: onLog,
  );
}
