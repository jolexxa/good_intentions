import 'package:analyzer/file_system/file_system.dart';
import 'package:good_intentions/good_intentions.dart';
import 'package:intentions_engine/intentions_engine.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockAnalyzerAdapter extends Mock implements AnalyzerAdapter {}

class _MockResourceProvider extends Mock implements ResourceProvider {}

class _MockFolder extends Mock implements Folder {}

const _basicCollection = CollectionResult(
  classes: [
    AnnotatedClass(
      name: 'UserApi',
      intention: Intention.dataSource,
      dependencies: {},
    ),
    AnnotatedClass(
      name: 'UserRepo',
      intention: Intention.repository,
      dependencies: {'UserApi'},
    ),
  ],
  untagged: ['JustAClass'],
);

const _pathDepCollection = CollectionResult(
  classes: [
    AnnotatedClass(
      name: 'MyRepo',
      intention: Intention.repository,
      dependencies: {'DepApi'},
    ),
    AnnotatedClass(
      name: 'DepApi',
      intention: Intention.dataSource,
      dependencies: {},
    ),
  ],
  untagged: [],
);

const _partOfCollection = CollectionResult(
  classes: [
    AnnotatedClass(
      name: 'MyOwner',
      intention: Intention.useCase,
      dependencies: {'MyHelper'},
    ),
    AnnotatedClass(
      name: 'MyHelper',
      intention: Intention.repository,
      dependencies: {'ConfigApi'},
      owner: 'MyOwner',
    ),
    AnnotatedClass(
      name: 'ConfigApi',
      intention: Intention.dataSource,
      dependencies: {},
    ),
  ],
  untagged: [],
);

void main() {
  late _MockAnalyzerAdapter mockAnalyzer;
  late _MockResourceProvider mockProvider;

  setUp(() {
    mockAnalyzer = _MockAnalyzerAdapter();
    mockProvider = _MockResourceProvider();
  });

  group('ClassCollector', () {
    test('collects annotated classes with dependencies from lib/', () async {
      final mockFolder = _MockFolder();
      when(() => mockProvider.getFolder('/root/lib')).thenReturn(mockFolder);
      when(() => mockFolder.exists).thenReturn(true);
      when(
        () => mockAnalyzer.analyze(any(), any()),
      ).thenAnswer((_) async => _basicCollection);

      final collector = ClassCollector(mockAnalyzer, mockProvider);
      final result = await collector.collect('/root');

      final names = result.classes.map((c) => c.name).toSet();
      expect(names, contains('UserApi'));
      expect(names, contains('UserRepo'));

      final repo = result.classes.firstWhere((c) => c.name == 'UserRepo');
      expect(repo.intention, Intention.repository);
      expect(repo.dependencies, contains('UserApi'));
      expect(result.untagged, ['JustAClass']);

      verify(() => mockAnalyzer.analyze('/root/lib', '/root')).called(1);
    });

    test('discovers annotated classes from path dependencies', () async {
      final mockFolder = _MockFolder();
      when(() => mockProvider.getFolder('/root/lib')).thenReturn(mockFolder);
      when(() => mockFolder.exists).thenReturn(true);
      when(
        () => mockAnalyzer.analyze(any(), any()),
      ).thenAnswer((_) async => _pathDepCollection);

      final collector = ClassCollector(mockAnalyzer, mockProvider);
      final result = await collector.collect('/root');

      final names = result.classes.map((c) => c.name).toSet();
      expect(names, contains('MyRepo'));
      expect(names, contains('DepApi'));
    });

    test('extracts @PartOf, dual annotations, and generic deps', () async {
      final mockFolder = _MockFolder();
      when(() => mockProvider.getFolder('/root/lib')).thenReturn(mockFolder);
      when(() => mockFolder.exists).thenReturn(true);
      when(
        () => mockAnalyzer.analyze(any(), any()),
      ).thenAnswer((_) async => _partOfCollection);

      final collector = ClassCollector(mockAnalyzer, mockProvider);
      final result = await collector.collect('/root');

      final helper = result.classes.firstWhere((c) => c.name == 'MyHelper');
      expect(helper.intention, Intention.repository);
      expect(helper.owner, 'MyOwner');
      expect(helper.dependencies, contains('ConfigApi'));
    });

    test('returns empty for package with no lib/ directory', () async {
      final mockFolder = _MockFolder();
      when(() => mockProvider.getFolder('/root/lib')).thenReturn(mockFolder);
      when(() => mockFolder.exists).thenReturn(false);

      final collector = ClassCollector(mockAnalyzer, mockProvider);
      final result = await collector.collect('/root');

      expect(result.classes, isEmpty);
      expect(result.untagged, isEmpty);
      verifyNever(() => mockAnalyzer.analyze(any(), any()));
    });

    test('always calls analyzer (no caching)', () async {
      final mockFolder = _MockFolder();
      when(() => mockProvider.getFolder('/root/lib')).thenReturn(mockFolder);
      when(() => mockFolder.exists).thenReturn(true);
      when(
        () => mockAnalyzer.analyze(any(), any()),
      ).thenAnswer((_) async => _basicCollection);

      final collector = ClassCollector(mockAnalyzer, mockProvider);

      await collector.collect('/root');
      await collector.collect('/root');

      verify(() => mockAnalyzer.analyze(any(), any())).called(2);
    });
  });
}
