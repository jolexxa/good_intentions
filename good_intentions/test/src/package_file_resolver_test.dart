import 'dart:convert';

import 'package:analyzer/file_system/memory_file_system.dart';
import 'package:good_intentions/good_intentions.dart';
import 'package:test/test.dart';

void main() {
  late MemoryResourceProvider mem;
  late PackageFileResolver resolver;

  setUp(() {
    mem = MemoryResourceProvider();
    resolver = PackageFileResolver(mem);
  });

  group('trackedFiles', () {
    test('includes lib/ .dart files', () {
      mem
        ..newFile('/root/lib/src/a.dart', 'class A {}')
        ..newFile('/root/lib/src/b.dart', 'class B {}');

      final uris = resolver.trackedFiles('/root');
      final paths = uris.map((u) => u.toFilePath()).toList();

      expect(paths, anyElement(endsWith('lib/src/a.dart')));
      expect(paths, anyElement(endsWith('lib/src/b.dart')));
    });

    test('includes pubspec.lock', () {
      mem
        ..newFile('/root/lib/src/a.dart', 'class A {}')
        ..newFile('/root/pubspec.lock', 'lock content');

      final uris = resolver.trackedFiles('/root');
      final paths = uris.map((u) => u.toFilePath()).toList();

      expect(paths, anyElement(endsWith('pubspec.lock')));
    });

    test('includes path dep pubspec.yaml', () {
      mem
        ..newFile('/root/lib/src/a.dart', 'class A {}')
        ..newFile('/dep/pubspec.yaml', 'name: dep\n')
        ..newFile(
          '/root/.dart_tool/package_config.json',
          jsonEncode({
            'packages': [
              {'name': 'dep', 'rootUri': 'file:///dep'},
            ],
          }),
        );

      final uris = resolver.trackedFiles('/root');
      final paths = uris.map((u) => u.toFilePath()).toList();

      expect(
        paths,
        anyElement(allOf(contains('dep'), endsWith('pubspec.yaml'))),
      );
    });

    test('includes path dep dart sources when dep uses intentions', () {
      mem
        ..newFile('/root/lib/src/a.dart', 'class A {}')
        ..newFile(
          '/dep/pubspec.yaml',
          'name: dep\ndependencies:\n  intentions: ^0.1.0\n',
        )
        ..newFile('/dep/lib/src/d.dart', 'class D {}')
        ..newFile(
          '/root/.dart_tool/package_config.json',
          jsonEncode({
            'packages': [
              {'name': 'dep', 'rootUri': 'file:///dep'},
            ],
          }),
        );

      final uris = resolver.trackedFiles('/root');
      final paths = uris.map((u) => u.toFilePath()).toList();

      expect(
        paths,
        anyElement(allOf(contains('dep'), endsWith('d.dart'))),
      );
    });

    test('excludes non-dart files in lib/', () {
      mem
        ..newFile('/root/lib/src/a.dart', 'class A {}')
        ..newFile('/root/lib/readme.txt', 'hello');

      final uris = resolver.trackedFiles('/root');
      final paths = uris.map((u) => u.toFilePath()).toList();

      expect(paths, isNot(anyElement(endsWith('.txt'))));
    });

    test('excludes pub-cache dependencies', () {
      mem
        ..newFile('/root/lib/src/a.dart', 'class A {}')
        ..newFile(
          '/Users/me/.pub-cache/hosted/some_pkg/pubspec.yaml',
          'name: some_pkg\ndependencies:\n  intentions: ^0.1.0\n',
        )
        ..newFile(
          '/root/.dart_tool/package_config.json',
          jsonEncode({
            'packages': [
              {
                'name': 'some_pkg',
                'rootUri': 'file:///Users/me/.pub-cache/hosted/some_pkg',
              },
            ],
          }),
        );

      final uris = resolver.trackedFiles('/root');
      final paths = uris.map((u) => u.toFilePath()).toList();

      expect(paths, isNot(anyElement(contains('.pub-cache'))));
    });

    test('returns empty when lib/ does not exist', () {
      final uris = resolver.trackedFiles('/root');
      expect(uris, isEmpty);
    });
  });

  group('readPackageName', () {
    test('reads package name from pubspec.yaml', () {
      mem.newFile('/root/pubspec.yaml', 'name: my_cool_pkg\n');

      expect(resolver.readPackageName('/root'), 'my_cool_pkg');
    });

    test('throws StateError when pubspec has no name field', () {
      mem.newFile('/root/pubspec.yaml', 'description: no name here\n');

      expect(
        () => resolver.readPackageName('/root'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('readPackageConfig', () {
    test('returns empty map when package_config.json is missing', () {
      final result = resolver.readPackageConfig('/root');
      expect(result, isEmpty);
    });

    test('parses package_config.json correctly', () {
      mem.newFile(
        '/root/.dart_tool/package_config.json',
        jsonEncode({
          'packages': [
            {'name': 'my_pkg', 'rootUri': 'file:///my_pkg'},
            {'name': 'dep', 'rootUri': '../dep'},
          ],
        }),
      );

      final config = resolver.readPackageConfig('/root');
      expect(config, contains('my_pkg'));
      expect(config, contains('dep'));
      expect(config['my_pkg'], '/my_pkg');
    });
  });

  group('isIntentionsPathDep', () {
    test('returns false for pub-cache packages', () {
      final config = {'some_pkg': '/Users/me/.pub-cache/hosted/some_pkg'};
      final cache = <String, bool>{};

      expect(
        resolver.isIntentionsPathDep('some_pkg', config, cache),
        isFalse,
      );
    });

    test('returns false for unknown packages', () {
      final config = <String, String>{};
      final cache = <String, bool>{};

      expect(
        resolver.isIntentionsPathDep('missing', config, cache),
        isFalse,
      );
    });

    test('caches results', () {
      final config = <String, String>{};
      final cache = <String, bool>{'cached_pkg': true};

      expect(
        resolver.isIntentionsPathDep('cached_pkg', config, cache),
        isTrue,
      );
    });

    test('returns true for path dep with intentions', () {
      mem.newFile(
        '/dep/pubspec.yaml',
        'name: dep\ndependencies:\n  intentions: ^0.1.0\n',
      );

      final config = {'dep': '/dep'};
      final cache = <String, bool>{};

      expect(
        resolver.isIntentionsPathDep('dep', config, cache),
        isTrue,
      );
    });

    test('returns false for path dep without intentions', () {
      mem.newFile('/dep/pubspec.yaml', 'name: dep\ndependencies:\n');

      final config = {'dep': '/dep'};
      final cache = <String, bool>{};

      expect(
        resolver.isIntentionsPathDep('dep', config, cache),
        isFalse,
      );
    });

    test('returns false when pubspec.yaml does not exist', () {
      final config = {'dep': '/dep'};
      final cache = <String, bool>{};

      expect(
        resolver.isIntentionsPathDep('dep', config, cache),
        isFalse,
      );
    });
  });
}
