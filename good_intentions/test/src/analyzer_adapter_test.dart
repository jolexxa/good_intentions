import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/context_root.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/session.dart';
import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/file_system/file_system.dart';
import 'package:analyzer/file_system/memory_file_system.dart';
import 'package:good_intentions/good_intentions.dart';
import 'package:intentions_engine/intentions_engine.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

// -- Mock classes -----------------------------------------------------------

class _MockCollection extends Mock implements AnalysisContextCollection {}

class _MockContext extends Mock implements AnalysisContext {}

class _MockContextRoot extends Mock implements ContextRoot {}

class _MockSession extends Mock implements AnalysisSession {}

class _MockResolvedUnit extends Mock implements ResolvedUnitResult {}

class _MockLibrary extends Mock implements LibraryElement {}

class _MockLibraryFragment extends Mock implements LibraryFragment {}

class _MockClass extends Mock implements ClassElement {}

class _MockConstructor extends Mock implements ConstructorElement {}

class _MockParam extends Mock implements FormalParameterElement {}

class _MockField extends Mock implements FieldElement {}

class _MockInterfaceType extends Mock implements InterfaceType {}

class _MockInterfaceElement extends Mock implements InterfaceElement {}

class _MockAnnotation extends Mock implements ElementAnnotation {}

class _MockDartObject extends Mock implements DartObject {}

class _MockMetadata extends Mock implements Metadata {}

class _MockPackageFileResolver extends Mock implements PackageFileResolver {}

class _MockResourceProvider extends Mock implements ResourceProvider {}

// -- Helpers ----------------------------------------------------------------

/// Builds a mock [ClassElement] with the given [name] and optional
/// annotation from `package:intentions/`.
_MockClass _buildMockClass(
  String name, {
  String? annotationTypeName,
  bool isPrivate = false,
  bool isAbstract = false,
  bool isInterface = false,
  List<FormalParameterElement> constructorParams = const [],
  List<FieldElement> fields = const [],
  String? partOfOwner,
}) {
  final cls = _MockClass();
  when(() => cls.name).thenReturn(name);
  when(() => cls.isPrivate).thenReturn(isPrivate);
  when(() => cls.isAbstract).thenReturn(isAbstract);
  when(() => cls.isInterface).thenReturn(isInterface);

  // Constructors.
  if (constructorParams.isNotEmpty) {
    final ctor = _MockConstructor();
    when(() => ctor.formalParameters).thenReturn(constructorParams);
    when(() => cls.constructors).thenReturn([ctor]);
  } else {
    final defaultCtor = _MockConstructor();
    when(() => defaultCtor.formalParameters).thenReturn([]);
    when(() => cls.constructors).thenReturn([defaultCtor]);
  }

  // Fields.
  when(() => cls.fields).thenReturn(fields);

  // Annotations.
  final annotations = <ElementAnnotation>[];

  if (annotationTypeName != null) {
    final annotation = _MockAnnotation();
    final dartObject = _MockDartObject();
    final interfaceType = _MockInterfaceType();
    final typeElement = _MockInterfaceElement();
    final mockLibrary = _MockLibrary();

    when(annotation.computeConstantValue).thenReturn(dartObject);
    when(() => dartObject.type).thenReturn(interfaceType);
    when(() => interfaceType.element).thenReturn(typeElement);
    when(() => typeElement.name).thenReturn(annotationTypeName);
    when(() => typeElement.library).thenReturn(mockLibrary);
    when(
      () => mockLibrary.uri,
    ).thenReturn(Uri.parse('package:intentions/src/annotations.dart'));

    // Handle @PartOf owner field.
    if (partOfOwner != null) {
      final ownerType = _MockInterfaceType();
      final ownerElement = _MockInterfaceElement();
      final ownerDartObject = _MockDartObject();
      when(() => dartObject.getField('owner')).thenReturn(ownerDartObject);
      when(ownerDartObject.toTypeValue).thenReturn(ownerType);
      when(() => ownerType.element).thenReturn(ownerElement);
      when(() => ownerElement.name).thenReturn(partOfOwner);
    } else {
      when(() => dartObject.getField('owner')).thenReturn(null);
    }

    annotations.add(annotation);
  }

  final metadata = _MockMetadata();
  when(() => metadata.annotations).thenReturn(annotations);
  when(() => cls.metadata).thenReturn(metadata);

  return cls;
}

/// Sets up a mock analyzer chain: collection → context → root → session.
({
  _MockCollection collection,
  _MockContext context,
  _MockContextRoot contextRoot,
  _MockSession session,
})
_buildMockAnalyzerChain({
  required List<String> analyzedFiles,
  required Map<String, SomeResolvedUnitResult> unitResults,
}) {
  final collection = _MockCollection();
  final context = _MockContext();
  final contextRoot = _MockContextRoot();
  final session = _MockSession();

  when(() => collection.contexts).thenReturn([context]);
  when(collection.dispose).thenAnswer((_) async {});
  when(() => context.contextRoot).thenReturn(contextRoot);
  when(contextRoot.analyzedFiles).thenReturn(analyzedFiles);
  when(() => context.currentSession).thenReturn(session);

  for (final entry in unitResults.entries) {
    when(
      () => session.getResolvedUnit(entry.key),
    ).thenAnswer((_) async => entry.value);
  }

  return (
    collection: collection,
    context: context,
    contextRoot: contextRoot,
    session: session,
  );
}

/// Builds a mock [LibraryElement] with the given [classes] and [uri].
_MockLibrary _buildMockLibrary({
  required Uri uri,
  required List<ClassElement> classes,
  List<LibraryElement> importedLibraries = const [],
  List<LibraryElement> exportedLibraries = const [],
}) {
  final lib = _MockLibrary();
  final fragment = _MockLibraryFragment();

  when(() => lib.uri).thenReturn(uri);
  when(() => lib.classes).thenReturn(classes);
  when(() => lib.firstFragment).thenReturn(fragment);
  when(() => fragment.importedLibraries).thenReturn(importedLibraries);
  when(() => lib.exportedLibraries).thenReturn(exportedLibraries);

  return lib;
}

/// Builds a mock [ResolvedUnitResult] backed by a [LibraryElement].
_MockResolvedUnit _buildMockUnitResult(
  LibraryElement library, {
  bool isPart = false,
}) {
  final unit = _MockResolvedUnit();
  when(() => unit.isPart).thenReturn(isPart);
  when(() => unit.libraryElement).thenReturn(library);
  return unit;
}

/// Builds a mock [FormalParameterElement] whose type is [interfaceType].
_MockParam _buildMockParam(InterfaceType interfaceType) {
  final param = _MockParam();
  when(() => param.type).thenReturn(interfaceType);
  return param;
}

/// Builds a mock [FieldElement] whose type is [interfaceType].
_MockField _buildMockField(
  InterfaceType interfaceType, {
  bool isStatic = false,
}) {
  final field = _MockField();
  when(() => field.type).thenReturn(interfaceType);
  when(() => field.isStatic).thenReturn(isStatic);
  return field;
}

/// Builds a mock [InterfaceType] backed by a mock element with [name].
/// Optionally includes [typeArguments] for generic type testing.
_MockInterfaceType _buildMockInterfaceType(
  String name, {
  List<InterfaceType> typeArguments = const [],
  String? annotationTypeName,
}) {
  final type = _MockInterfaceType();
  final element = annotationTypeName != null
      ? _buildMockClass(name, annotationTypeName: annotationTypeName)
      : _MockInterfaceElement();
  when(() => element.name).thenReturn(name);
  when(() => type.element).thenReturn(element);
  when(() => type.typeArguments).thenReturn(typeArguments);
  return type;
}

// -- Tests ------------------------------------------------------------------

void main() {
  late _MockPackageFileResolver mockResolver;
  late _MockResourceProvider mockProvider;
  late AnalyzerAdapter adapter;

  setUp(() {
    mockResolver = _MockPackageFileResolver();
    mockProvider = _MockResourceProvider();
    adapter = AnalyzerAdapter(mockResolver, mockProvider);

    // Default stubs for Phase 2 — most tests don't care about these.
    when(
      () => mockResolver.readPackageConfig(any()),
    ).thenReturn(<String, String>{});
    when(
      () => mockResolver.isIntentionsPathDep(any(), any(), any()),
    ).thenReturn(false);
  });

  tearDown(() {
    AnalyzerAdapter.createCollection = AnalyzerAdapter.defaultCreateCollection;
  });

  group('AnalyzerAdapter', () {
    test('collects annotated classes from analyzed files', () async {
      when(() => mockResolver.readPackageName('/root')).thenReturn('test_pkg');

      final apiClass = _buildMockClass(
        'UserApi',
        annotationTypeName: 'DataSource',
      );
      final repoClass = _buildMockClass(
        'UserRepo',
        annotationTypeName: 'Repository',
      );
      final lib = _buildMockLibrary(
        uri: Uri.parse('package:test_pkg/test_pkg.dart'),
        classes: [apiClass, repoClass],
      );
      final unitResult = _buildMockUnitResult(lib);

      final chain = _buildMockAnalyzerChain(
        analyzedFiles: ['/root/lib/src/api.dart'],
        unitResults: {'/root/lib/src/api.dart': unitResult},
      );
      AnalyzerAdapter.createCollection =
          ({
            required includedPaths,
            required resourceProvider,
            sdkPath,
          }) => chain.collection;

      final result = await adapter.analyze('/root/lib', '/root');

      final names = result.classes.map((c) => c.name).toSet();
      expect(names, contains('UserApi'));
      expect(names, contains('UserRepo'));
    });

    test('skips non-dart files', () async {
      when(() => mockResolver.readPackageName('/root')).thenReturn('test_pkg');

      final chain = _buildMockAnalyzerChain(
        analyzedFiles: ['/root/lib/readme.txt', '/root/lib/src/a.dart'],
        unitResults: {},
      );

      final lib = _buildMockLibrary(
        uri: Uri.parse('package:test_pkg/a.dart'),
        classes: [_buildMockClass('A', annotationTypeName: 'Model')],
      );
      final unit = _buildMockUnitResult(lib);
      when(
        () => chain.session.getResolvedUnit('/root/lib/src/a.dart'),
      ).thenAnswer((_) async => unit);

      AnalyzerAdapter.createCollection =
          ({
            required includedPaths,
            required resourceProvider,
            sdkPath,
          }) => chain.collection;

      final result = await adapter.analyze('/root/lib', '/root');

      // Only the .dart file was processed.
      expect(result.classes, hasLength(1));
      expect(result.classes.first.name, 'A');
    });

    test('skips part files', () async {
      when(() => mockResolver.readPackageName('/root')).thenReturn('test_pkg');

      final lib = _buildMockLibrary(
        uri: Uri.parse('package:test_pkg/a.dart'),
        classes: [_buildMockClass('A', annotationTypeName: 'Model')],
      );
      final partUnit = _buildMockUnitResult(lib, isPart: true);

      final chain = _buildMockAnalyzerChain(
        analyzedFiles: ['/root/lib/src/a.dart'],
        unitResults: {'/root/lib/src/a.dart': partUnit},
      );
      AnalyzerAdapter.createCollection =
          ({
            required includedPaths,
            required resourceProvider,
            sdkPath,
          }) => chain.collection;

      final result = await adapter.analyze('/root/lib', '/root');

      expect(result.classes, isEmpty);
    });

    test('skips private classes', () async {
      when(() => mockResolver.readPackageName('/root')).thenReturn('test_pkg');

      final lib = _buildMockLibrary(
        uri: Uri.parse('package:test_pkg/a.dart'),
        classes: [
          _buildMockClass('_Private', isPrivate: true),
          _buildMockClass('Public', annotationTypeName: 'Model'),
        ],
      );
      final unit = _buildMockUnitResult(lib);

      final chain = _buildMockAnalyzerChain(
        analyzedFiles: ['/root/lib/src/a.dart'],
        unitResults: {'/root/lib/src/a.dart': unit},
      );
      AnalyzerAdapter.createCollection =
          ({
            required includedPaths,
            required resourceProvider,
            sdkPath,
          }) => chain.collection;

      final result = await adapter.analyze('/root/lib', '/root');

      expect(result.classes.map((c) => c.name), ['Public']);
    });

    test('tracks untagged concrete classes', () async {
      when(() => mockResolver.readPackageName('/root')).thenReturn('test_pkg');

      final lib = _buildMockLibrary(
        uri: Uri.parse('package:test_pkg/a.dart'),
        classes: [
          _buildMockClass('Plain'),
          _buildMockClass('AbstractThing', isAbstract: true),
          _buildMockClass('InterfaceThing', isInterface: true),
        ],
      );
      final unit = _buildMockUnitResult(lib);

      final chain = _buildMockAnalyzerChain(
        analyzedFiles: ['/root/lib/src/a.dart'],
        unitResults: {'/root/lib/src/a.dart': unit},
      );
      AnalyzerAdapter.createCollection =
          ({
            required includedPaths,
            required resourceProvider,
            sdkPath,
          }) => chain.collection;

      final result = await adapter.analyze('/root/lib', '/root');

      // Only concrete, non-abstract, non-interface classes are untagged.
      expect(result.untagged, ['Plain']);
    });

    test('walks transitive imports for path dep classes', () async {
      when(() => mockResolver.readPackageName('/root')).thenReturn('root_pkg');
      when(
        () => mockResolver.readPackageConfig('/root'),
      ).thenReturn({'dep': '/dep'});
      when(
        () => mockResolver.isIntentionsPathDep('dep', any(), any()),
      ).thenReturn(true);

      // Local library imports a dep library.
      final depClass = _buildMockClass(
        'DepApi',
        annotationTypeName: 'DataSource',
      );
      final depLib = _buildMockLibrary(
        uri: Uri.parse('package:dep/dep_api.dart'),
        classes: [depClass],
      );
      final localLib = _buildMockLibrary(
        uri: Uri.parse('package:root_pkg/repo.dart'),
        classes: [
          _buildMockClass('MyRepo', annotationTypeName: 'Repository'),
        ],
        importedLibraries: [depLib],
      );
      final unit = _buildMockUnitResult(localLib);

      final chain = _buildMockAnalyzerChain(
        analyzedFiles: ['/root/lib/src/repo.dart'],
        unitResults: {'/root/lib/src/repo.dart': unit},
      );
      AnalyzerAdapter.createCollection =
          ({
            required includedPaths,
            required resourceProvider,
            sdkPath,
          }) => chain.collection;

      final result = await adapter.analyze('/root/lib', '/root');

      final names = result.classes.map((c) => c.name).toSet();
      expect(names, contains('MyRepo'));
      expect(names, contains('DepApi'));
    });

    test('skips dart: and same-package imports in Phase 2', () async {
      when(() => mockResolver.readPackageName('/root')).thenReturn('test_pkg');

      final dartLib = _buildMockLibrary(
        uri: Uri.parse('dart:core'),
        classes: [],
      );
      final samePackageLib = _buildMockLibrary(
        uri: Uri.parse('package:test_pkg/other.dart'),
        classes: [
          _buildMockClass('Other', annotationTypeName: 'Model'),
        ],
      );
      final localLib = _buildMockLibrary(
        uri: Uri.parse('package:test_pkg/main.dart'),
        classes: [
          _buildMockClass('Main', annotationTypeName: 'View'),
        ],
        importedLibraries: [dartLib, samePackageLib],
      );
      final unit = _buildMockUnitResult(localLib);

      final chain = _buildMockAnalyzerChain(
        analyzedFiles: ['/root/lib/main.dart'],
        unitResults: {'/root/lib/main.dart': unit},
      );
      AnalyzerAdapter.createCollection =
          ({
            required includedPaths,
            required resourceProvider,
            sdkPath,
          }) => chain.collection;

      final result = await adapter.analyze('/root/lib', '/root');

      // Only the local class from Phase 1 — dart: and same-package
      // imports are skipped in Phase 2.
      expect(result.classes.map((c) => c.name), ['Main']);
    });

    test('extracts @PartOf with owner', () async {
      when(() => mockResolver.readPackageName('/root')).thenReturn('test_pkg');

      final lib = _buildMockLibrary(
        uri: Uri.parse('package:test_pkg/a.dart'),
        classes: [
          _buildMockClass(
            'MyHelper',
            annotationTypeName: 'PartOf',
            partOfOwner: 'MyOwner',
          ),
        ],
      );
      final unit = _buildMockUnitResult(lib);

      final chain = _buildMockAnalyzerChain(
        analyzedFiles: ['/root/lib/src/a.dart'],
        unitResults: {'/root/lib/src/a.dart': unit},
      );
      AnalyzerAdapter.createCollection =
          ({
            required includedPaths,
            required resourceProvider,
            sdkPath,
          }) => chain.collection;

      final result = await adapter.analyze('/root/lib', '/root');

      final helper = result.classes.first;
      expect(helper.name, 'MyHelper');
      expect(helper.intention, Intention.partOf);
      expect(helper.owner, 'MyOwner');
    });

    test('disposes the collection after analysis', () async {
      when(() => mockResolver.readPackageName('/root')).thenReturn('test_pkg');

      final chain = _buildMockAnalyzerChain(
        analyzedFiles: [],
        unitResults: {},
      );
      AnalyzerAdapter.createCollection =
          ({
            required includedPaths,
            required resourceProvider,
            sdkPath,
          }) => chain.collection;

      await adapter.analyze('/root/lib', '/root');

      verify(chain.collection.dispose).called(1);
    });

    test('createCollection defaults to defaultCreateCollection', () {
      expect(
        AnalyzerAdapter.createCollection,
        same(AnalyzerAdapter.defaultCreateCollection),
      );
    });

    test('defaultCreateCollection creates cache dir and returns '
        'a collection', () async {
      // AnalysisContextCollectionImpl needs a minimal SDK structure.
      final mem = MemoryResourceProvider();
      const sdkPath = '/sdk';
      mem
        ..newFile('$sdkPath/version', '3.12.0')
        ..newFile(
          '$sdkPath/lib/_internal/allowed_experiments.json',
          '{"version":1,"experimentSets":{},"experiments":{}}',
        )
        ..newFile(
          '$sdkPath/lib/_internal/sdk_library_metadata/lib/libraries.dart',
          'const Map<String, LibraryInfo> libraries = const {'
              "  'core': const LibraryInfo('core/core.dart'), "
              '};\n'
              'class LibraryInfo {\n'
              '  final String path;\n'
              '  const LibraryInfo(this.path);\n'
              '}\n',
        )
        ..newFile('$sdkPath/lib/core/core.dart', 'library dart.core;')
        ..newFile(
          '$sdkPath/lib/libraries.json',
          '{"comment":"","vm":{"libraries":{}},'
              '"dart2js":{"libraries":{}},"dartdevc":{"libraries":{}}}',
        )
        ..newFolder('/root/lib');

      final collection = AnalyzerAdapter.defaultCreateCollection(
        includedPaths: ['/root/lib'],
        resourceProvider: mem,
        sdkPath: sdkPath,
      );

      expect(collection, isA<AnalysisContextCollection>());
      // MemoryResourceProvider.getStateLocation('analysis-driver')
      // resolves to /user/home/analysis-driver.
      expect(
        mem.getFolder('/user/home/analysis-driver').exists,
        isTrue,
      );
      await collection.dispose();
    });

    test('extracts dependencies from constructor params', () async {
      when(() => mockResolver.readPackageName('/root')).thenReturn('test_pkg');

      final depType = _buildMockInterfaceType('ApiClient');
      final cls = _buildMockClass(
        'Repo',
        annotationTypeName: 'Repository',
        constructorParams: [_buildMockParam(depType)],
      );
      final lib = _buildMockLibrary(
        uri: Uri.parse('package:test_pkg/repo.dart'),
        classes: [cls],
      );
      final unit = _buildMockUnitResult(lib);
      final chain = _buildMockAnalyzerChain(
        analyzedFiles: ['/root/lib/repo.dart'],
        unitResults: {'/root/lib/repo.dart': unit},
      );
      AnalyzerAdapter.createCollection =
          ({
            required includedPaths,
            required resourceProvider,
            sdkPath,
          }) => chain.collection;

      final result = await adapter.analyze('/root/lib', '/root');

      final repo = result.classes.firstWhere((c) => c.name == 'Repo');
      expect(repo.dependencies, contains('ApiClient'));
    });

    test('extracts dependencies from instance fields', () async {
      when(() => mockResolver.readPackageName('/root')).thenReturn('test_pkg');

      final depType = _buildMockInterfaceType('Config');
      final cls = _buildMockClass(
        'Service',
        annotationTypeName: 'UseCase',
        fields: [_buildMockField(depType)],
      );
      final lib = _buildMockLibrary(
        uri: Uri.parse('package:test_pkg/service.dart'),
        classes: [cls],
      );
      final unit = _buildMockUnitResult(lib);
      final chain = _buildMockAnalyzerChain(
        analyzedFiles: ['/root/lib/service.dart'],
        unitResults: {'/root/lib/service.dart': unit},
      );
      AnalyzerAdapter.createCollection =
          ({
            required includedPaths,
            required resourceProvider,
            sdkPath,
          }) => chain.collection;

      final result = await adapter.analyze('/root/lib', '/root');

      final svc = result.classes.firstWhere((c) => c.name == 'Service');
      expect(svc.dependencies, contains('Config'));
    });

    test('skips static fields for dependencies', () async {
      when(() => mockResolver.readPackageName('/root')).thenReturn('test_pkg');

      final depType = _buildMockInterfaceType('StaticDep');
      final cls = _buildMockClass(
        'Service',
        annotationTypeName: 'UseCase',
        fields: [_buildMockField(depType, isStatic: true)],
      );
      final lib = _buildMockLibrary(
        uri: Uri.parse('package:test_pkg/service.dart'),
        classes: [cls],
      );
      final unit = _buildMockUnitResult(lib);
      final chain = _buildMockAnalyzerChain(
        analyzedFiles: ['/root/lib/service.dart'],
        unitResults: {'/root/lib/service.dart': unit},
      );
      AnalyzerAdapter.createCollection =
          ({
            required includedPaths,
            required resourceProvider,
            sdkPath,
          }) => chain.collection;

      final result = await adapter.analyze('/root/lib', '/root');

      final svc = result.classes.firstWhere((c) => c.name == 'Service');
      expect(svc.dependencies, isNot(contains('StaticDep')));
    });

    test('extracts generic type arguments recursively', () async {
      when(() => mockResolver.readPackageName('/root')).thenReturn('test_pkg');

      // Map<String, ApiClient> — should extract both Map, String, ApiClient.
      final innerType = _buildMockInterfaceType('ApiClient');
      final stringType = _buildMockInterfaceType('String');
      final mapType = _buildMockInterfaceType(
        'Map',
        typeArguments: [stringType, innerType],
      );

      final cls = _buildMockClass(
        'Repo',
        annotationTypeName: 'Repository',
        constructorParams: [_buildMockParam(mapType)],
      );
      final lib = _buildMockLibrary(
        uri: Uri.parse('package:test_pkg/repo.dart'),
        classes: [cls],
      );
      final unit = _buildMockUnitResult(lib);
      final chain = _buildMockAnalyzerChain(
        analyzedFiles: ['/root/lib/repo.dart'],
        unitResults: {'/root/lib/repo.dart': unit},
      );
      AnalyzerAdapter.createCollection =
          ({
            required includedPaths,
            required resourceProvider,
            sdkPath,
          }) => chain.collection;

      final result = await adapter.analyze('/root/lib', '/root');

      final repo = result.classes.firstWhere((c) => c.name == 'Repo');
      expect(repo.dependencies, containsAll(['Map', 'String', 'ApiClient']));
    });

    test('discovers externally-annotated classes from deps', () async {
      when(() => mockResolver.readPackageName('/root')).thenReturn('test_pkg');

      // Constructor param whose type element is a ClassElement with
      // an intentions annotation — should be discovered as external.
      final externalType = _buildMockInterfaceType(
        'ExternalApi',
        annotationTypeName: 'DataSource',
      );
      final cls = _buildMockClass(
        'Repo',
        annotationTypeName: 'Repository',
        constructorParams: [_buildMockParam(externalType)],
      );
      final lib = _buildMockLibrary(
        uri: Uri.parse('package:test_pkg/repo.dart'),
        classes: [cls],
      );
      final unit = _buildMockUnitResult(lib);
      final chain = _buildMockAnalyzerChain(
        analyzedFiles: ['/root/lib/repo.dart'],
        unitResults: {'/root/lib/repo.dart': unit},
      );
      AnalyzerAdapter.createCollection =
          ({
            required includedPaths,
            required resourceProvider,
            sdkPath,
          }) => chain.collection;

      final result = await adapter.analyze('/root/lib', '/root');

      final names = result.classes.map((c) => c.name).toSet();
      expect(names, contains('ExternalApi'));
      final ext = result.classes.firstWhere((c) => c.name == 'ExternalApi');
      expect(ext.intention, Intention.dataSource);
    });

    test('analyze passes resourceProvider to createCollection', () async {
      when(() => mockResolver.readPackageName('/root')).thenReturn('test_pkg');

      late ResourceProvider receivedProvider;

      AnalyzerAdapter.createCollection =
          ({
            required includedPaths,
            required resourceProvider,
            sdkPath,
          }) {
            receivedProvider = resourceProvider;
            return _buildMockAnalyzerChain(
              analyzedFiles: [],
              unitResults: {},
            ).collection;
          };

      await adapter.analyze('/root/lib', '/root');

      expect(receivedProvider, same(mockProvider));
    });
  });
}
