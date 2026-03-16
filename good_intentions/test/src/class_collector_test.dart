import 'dart:io';

import 'package:good_intentions/good_intentions.dart';
import 'package:intentions_engine/intentions_engine.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Creates a minimal package, runs `dart pub get`, returns the root path.
Future<String> _createPackage(
  Directory parent,
  String packageName, {
  Map<String, String> sources = const {},
  Map<String, String> pathDeps = const {},
}) async {
  final root = Directory(p.join(parent.path, packageName))..createSync();

  final depLines = StringBuffer()
    ..writeln('  intentions: ^0.1.0');
  for (final entry in pathDeps.entries) {
    depLines
      ..writeln('  ${entry.key}:')
      ..writeln('    path: ${entry.value}');
  }

  File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: $packageName
publish_to: none
environment:
  sdk: ^3.11.0
dependencies:
${depLines.toString().trimRight()}
''');

  for (final entry in sources.entries) {
    final file = File(p.join(root.path, entry.key));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(entry.value);
  }

  final result = await Process.run(
    'dart',
    ['pub', 'get'],
    workingDirectory: root.path,
  );
  if (result.exitCode != 0) {
    throw StateError(
      'dart pub get failed:\n${result.stdout}\n${result.stderr}',
    );
  }

  return root.path;
}

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('good_intentions_test_');
  });

  tearDown(() {
    ClassCollector.collectOverride = null;
    tmpDir.deleteSync(recursive: true);
  });

  group('ClassCollector', () {
    test('collects annotated classes with dependencies from lib/', () async {
      final root = await _createPackage(tmpDir, 'test_pkg', sources: {
        'lib/src/user_api.dart': '''
import 'package:intentions/intentions.dart';

@dataSource
class UserApi {
  const UserApi();
}
''',
        'lib/src/user_repo.dart': '''
import 'package:intentions/intentions.dart';
import 'package:test_pkg/src/user_api.dart';

@repository
class UserRepo {
  const UserRepo(this.api);
  final UserApi api;
}
''',
        'lib/src/plain.dart': '''
class JustAClass {
  const JustAClass();
}

abstract class AbstractThing {}

interface class InterfaceThing {}
''',
      });

      final (classes, untagged) = await ClassCollector.collect(root);

      final names = classes.map((c) => c.name).toSet();
      expect(names, contains('UserApi'));
      expect(names, contains('UserRepo'));

      final repo = classes.firstWhere((c) => c.name == 'UserRepo');
      expect(repo.intention, Intention.repository);
      expect(repo.dependencies, contains('UserApi'));

      // Only concrete, non-abstract, non-interface classes are untagged.
      expect(untagged, ['JustAClass']);
    });

    test('discovers annotated classes from path dependencies', () async {
      final depRoot = await _createPackage(tmpDir, 'dep_pkg', sources: {
        'lib/src/dep_api.dart': '''
import 'package:intentions/intentions.dart';

@dataSource
class DepApi {
  const DepApi();
}
''',
      });

      final root = await _createPackage(
        tmpDir,
        'root_pkg',
        sources: {
          'lib/src/repo.dart': '''
import 'package:intentions/intentions.dart';
import 'package:dep_pkg/src/dep_api.dart';

@repository
class MyRepo {
  const MyRepo(this.api);
  final DepApi api;
}
''',
        },
        pathDeps: {'dep_pkg': depRoot},
      );

      final (classes, _) = await ClassCollector.collect(root);

      final names = classes.map((c) => c.name).toSet();
      expect(names, contains('MyRepo'));
      expect(names, contains('DepApi'));
    });

    test('extracts @PartOf, dual annotations, and generic deps', () async {
      final root = await _createPackage(tmpDir, 'test_pkg', sources: {
        'lib/src/owner.dart': '''
import 'package:intentions/intentions.dart';
import 'package:test_pkg/src/helper.dart';

@useCase
class MyOwner {
  const MyOwner(this.helper);
  final MyHelper helper;
}
''',
        'lib/src/helper.dart': '''
import 'package:intentions/intentions.dart';
import 'package:test_pkg/src/owner.dart';
import 'package:test_pkg/src/api.dart';

@repository
@PartOf(MyOwner)
class MyHelper {
  const MyHelper(this.apis);
  final Map<String, ConfigApi> apis;
}
''',
        'lib/src/api.dart': '''
import 'package:intentions/intentions.dart';

@dataSource
class ConfigApi {
  const ConfigApi();
}
''',
      });

      final (classes, _) = await ClassCollector.collect(root);

      final helper = classes.firstWhere((c) => c.name == 'MyHelper');
      expect(helper.intention, Intention.repository);
      expect(helper.owner, 'MyOwner');
      expect(helper.dependencies, contains('ConfigApi'));
    });

    test('returns empty for package with no lib/ directory', () async {
      final root = Directory(p.join(tmpDir.path, 'empty_pkg'))..createSync();
      File(p.join(root.path, 'pubspec.yaml')).writeAsStringSync('''
name: empty_pkg
publish_to: none
environment:
  sdk: ^3.11.0
dependencies:
  intentions: ^0.1.0
''');
      await Process.run(
        'dart',
        ['pub', 'get'],
        workingDirectory: root.path,
      );

      final (classes, untagged) = await ClassCollector.collect(root.path);

      expect(classes, isEmpty);
      expect(untagged, isEmpty);
    });

    test('collectOverride bypasses analyzer', () async {
      ClassCollector.collectOverride = (_) async => (
            const [
              AnnotatedClass(
                name: 'Fake',
                intention: Intention.model,
                dependencies: {},
              ),
            ],
            const <String>['FakeUntagged'],
          );

      final (classes, untagged) =
          await ClassCollector.collect('/nonexistent');

      expect(classes.single.name, 'Fake');
      expect(untagged, ['FakeUntagged']);
    });
  });
}
