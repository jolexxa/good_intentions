import 'package:analyzer/file_system/memory_file_system.dart';
import 'package:good_intentions/good_intentions.dart';
import 'package:hooks/hooks.dart';
import 'package:intentions_engine/intentions_engine.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

class _MockClassCollector extends Mock implements ClassCollector {}

class _MockValidationReporter extends Mock implements ValidationReporter {}

class _MockPumlWriter extends Mock implements PumlWriter {}

class _MockPackageFileResolver extends Mock implements PackageFileResolver {}

class _MockArchitectureValidator extends Mock
    implements ArchitectureValidator {}

class _FakeDependencyGraph extends Fake implements DependencyGraph {}

const _validCollection = CollectionResult(
  classes: [
    AnnotatedClass(
      name: 'Repo',
      intention: Intention.repository,
      dependencies: {'Api'},
    ),
    AnnotatedClass(
      name: 'Api',
      intention: Intention.dataSource,
      dependencies: {},
    ),
  ],
  untagged: <String>['Untagged'],
);

const _violatingCollection = CollectionResult(
  classes: [
    AnnotatedClass(
      name: 'MyCubit',
      intention: Intention.viewModel,
      dependencies: {},
    ),
    AnnotatedClass(
      name: 'BadApi',
      intention: Intention.dataSource,
      dependencies: {'MyCubit'},
    ),
  ],
  untagged: <String>[],
);

void main() {
  group('ArchitectureReport', () {
    test('hasErrors returns true when error results present', () {
      final report = ArchitectureReport(
        classes: const [],
        untagged: const [],
        graph: DependencyGraph(const []),
        results: const [
          ValidationResult(severity: Severity.error, message: 'bad'),
        ],
        puml: '',
      );

      expect(report.hasErrors, isTrue);
      expect(report.errors, hasLength(1));
    });

    test('hasErrors returns false when no error results', () {
      final report = ArchitectureReport(
        classes: const [],
        untagged: const [],
        graph: DependencyGraph(const []),
        results: const [
          ValidationResult(severity: Severity.warning, message: 'hmm'),
          ValidationResult(severity: Severity.ok, message: 'fine'),
        ],
        puml: '',
      );

      expect(report.hasErrors, isFalse);
      expect(report.errors, isEmpty);
    });

    test('hasErrors returns false for empty results', () {
      final report = ArchitectureReport(
        classes: const [],
        untagged: const [],
        graph: DependencyGraph(const []),
        results: const [],
        puml: '',
      );

      expect(report.hasErrors, isFalse);
    });
  });

  group('ArchitectureValidator.withDefaults', () {
    test('returns validator wired with correct dependencies', () {
      final mem = MemoryResourceProvider();

      final validator = ArchitectureValidator.withDefaults(
        resourceProvider: mem,
      );

      expect(validator.resolver, isA<PackageFileResolver>());
      expect(validator.collector, isA<ClassCollector>());
      expect(validator.reporter, isA<ValidationReporter>());
      expect(validator.pumlWriter, isA<PumlWriter>());
      expect(validator.resolver.resourceProvider, same(mem));
    });
  });

  group('ArchitectureValidator static shims', () {
    test('createValidator defaults to defaultCreateValidator', () {
      expect(
        ArchitectureValidator.createValidator,
        same(ArchitectureValidator.defaultCreateValidator),
      );
    });

    test('defaultCreateValidator returns a valid validator', () {
      final validator = ArchitectureValidator.defaultCreateValidator();

      expect(validator, isA<ArchitectureValidator>());
      expect(validator.resolver, isA<PackageFileResolver>());
    });

    test('buildRunner defaults to defaultBuildRunner', () {
      expect(
        ArchitectureValidator.buildRunner,
        same(ArchitectureValidator.defaultBuildRunner),
      );
    });
  });

  group('ArchitectureValidator instance', () {
    late MemoryResourceProvider mem;
    late _MockClassCollector mockCollector;
    late _MockValidationReporter mockReporter;
    late _MockPumlWriter mockPumlWriter;
    late _MockPackageFileResolver mockResolver;
    late ArchitectureValidator validator;

    setUpAll(() {
      registerFallbackValue(_FakeDependencyGraph());
      registerFallbackValue(const <ValidationResult>[]);
    });

    setUp(() {
      mem = MemoryResourceProvider();
      mockCollector = _MockClassCollector();
      mockReporter = _MockValidationReporter();
      mockPumlWriter = _MockPumlWriter();
      mockResolver = _MockPackageFileResolver();
      when(() => mockResolver.resourceProvider).thenReturn(mem);
      validator = ArchitectureValidator(
        resolver: mockResolver,
        collector: mockCollector,
        reporter: mockReporter,
        pumlWriter: mockPumlWriter,
      );
    });

    group('analyze', () {
      test('returns report with classes and validation', () async {
        when(
          () => mockCollector.collect('/root'),
        ).thenAnswer((_) async => _validCollection);
        when(() => mockReporter.validateAll(any())).thenReturn(const []);
        when(
          () => mockPumlWriter.write(
            any(),
            any(),
            validationResults: any(named: 'validationResults'),
          ),
        ).thenReturn('@startuml\nRepo --> Api\n@enduml\n');

        final report = await validator.analyze(
          packageRoot: '/root',
          packageName: 'test_pkg',
        );

        expect(report.classes, hasLength(2));
        expect(report.hasErrors, isFalse);
        expect(report.untagged, contains('Untagged'));
        expect(report.puml, contains('@startuml'));
        expect(report.puml, contains('Repo --> Api'));
      });

      test('detects architecture violations', () async {
        when(
          () => mockCollector.collect('/root'),
        ).thenAnswer((_) async => _violatingCollection);
        when(() => mockReporter.validateAll(any())).thenReturn(const [
          ValidationResult(
            severity: Severity.error,
            message: 'BadApi violates rules',
          ),
        ]);
        when(
          () => mockPumlWriter.write(
            any(),
            any(),
            validationResults: any(named: 'validationResults'),
          ),
        ).thenReturn('@startuml\n@enduml\n');

        final report = await validator.analyze(
          packageRoot: '/root',
          packageName: 'test_pkg',
        );

        expect(report.hasErrors, isTrue);
        expect(report.errors.first.message, contains('BadApi'));
      });

      test('reads package name from resolver when not provided', () async {
        when(
          () => mockResolver.readPackageName('/root'),
        ).thenReturn('auto_pkg');
        when(
          () => mockCollector.collect('/root'),
        ).thenAnswer((_) async => _validCollection);
        when(() => mockReporter.validateAll(any())).thenReturn(const []);
        when(
          () => mockPumlWriter.write(
            any(),
            'auto_pkg',
            validationResults: any(named: 'validationResults'),
          ),
        ).thenReturn('@startuml\nauto_pkg\n@enduml\n');

        final report = await validator.analyze(packageRoot: '/root');

        expect(report.puml, contains('auto_pkg'));
        verify(() => mockResolver.readPackageName('/root')).called(1);
      });
    });

    group('validatePackage', () {
      test('writes puml file and logs OK', () async {
        when(
          () => mockCollector.collect('/root'),
        ).thenAnswer((_) async => _validCollection);
        when(() => mockReporter.validateAll(any())).thenReturn(const []);
        when(
          () => mockPumlWriter.write(
            any(),
            any(),
            validationResults: any(named: 'validationResults'),
          ),
        ).thenReturn('@startuml\ndiagram\n@enduml\n');

        final buf = StringBuffer();
        await validator.validatePackage(
          packageRoot: '/root',
          packageName: 'test_pkg',
          logger: Logger(buf),
        );

        final pumlFile = mem.getFile('/root/lib/architecture.g.puml');
        expect(pumlFile.exists, isTrue);
        expect(pumlFile.readAsStringSync(), contains('@startuml'));
        expect(
          buf.toString(),
          contains('${Logger.prefix} Architecture OK.'),
        );
      });

      test('throws BuildError on architecture violations', () async {
        when(
          () => mockCollector.collect('/root'),
        ).thenAnswer((_) async => _violatingCollection);
        when(() => mockReporter.validateAll(any())).thenReturn(const [
          ValidationResult(
            severity: Severity.error,
            message: 'violation',
          ),
        ]);
        when(
          () => mockPumlWriter.write(
            any(),
            any(),
            validationResults: any(named: 'validationResults'),
          ),
        ).thenReturn('@startuml\n@enduml\n');

        expect(
          () => validator.validatePackage(
            packageRoot: '/root',
            packageName: 'test_pkg',
            logger: Logger(StringBuffer()),
          ),
          throwsA(isA<BuildError>()),
        );
      });

      test('reports untagged and error results to logger', () async {
        when(() => mockCollector.collect('/root')).thenAnswer(
          (_) async => const CollectionResult(
            classes: [],
            untagged: ['Orphan'],
          ),
        );
        when(() => mockReporter.validateAll(any())).thenReturn(const [
          ValidationResult(severity: Severity.error, message: 'bad dep'),
        ]);
        when(
          () => mockPumlWriter.write(
            any(),
            any(),
            validationResults: any(named: 'validationResults'),
          ),
        ).thenReturn('');

        final buf = StringBuffer();
        await expectLater(
          () => validator.validatePackage(
            packageRoot: '/root',
            packageName: 'test_pkg',
            logger: Logger(buf),
          ),
          throwsA(isA<BuildError>()),
        );

        final output = buf.toString();
        expect(
          output,
          contains(
            '${Logger.prefix} WARN: Orphan has no intention '
            'annotation.',
          ),
        );
        expect(output, contains('${Logger.prefix} ERROR: bad dep'));
      });
    });
  });

  group('ArchitectureValidator.validate', () {
    late _MockArchitectureValidator mockValidator;
    late _MockPackageFileResolver mockResolver;

    setUpAll(() {
      registerFallbackValue(Uri.file('/'));
      registerFallbackValue(Logger(StringBuffer()));
    });

    setUp(() {
      mockValidator = _MockArchitectureValidator();
      mockResolver = _MockPackageFileResolver();
      when(() => mockValidator.resolver).thenReturn(mockResolver);
    });

    tearDown(() {
      ArchitectureValidator.createValidator =
          ArchitectureValidator.defaultCreateValidator;
      ArchitectureValidator.buildRunner =
          ArchitectureValidator.defaultBuildRunner;
    });

    test(
      'declares tracked files as hook dependencies and runs validation',
      () async {
        final trackedUris = [
          Uri.file('/root/lib/src/a.dart'),
          Uri.file('/root/lib/src/b.dart'),
        ];
        when(() => mockResolver.trackedFiles(any())).thenReturn(trackedUris);
        when(
          () => mockValidator.validatePackage(
            packageRoot: any(named: 'packageRoot'),
            packageName: any(named: 'packageName'),
            logger: any(named: 'logger'),
          ),
        ).thenAnswer((_) async {});

        ArchitectureValidator.createValidator = () => mockValidator;

        late BuildOutputBuilder capturedOutput;

        ArchitectureValidator.buildRunner = (args, callback) async {
          final inputBuilder = BuildInputBuilder()
            ..setupShared(
              packageRoot: Uri.directory('/root/'),
              packageName: 'test_pkg',
              outputFile: Uri.file('/tmp/output.json'),
              outputDirectoryShared: Uri.directory('/tmp/shared/'),
            )
            ..setupBuildInput();
          final input = inputBuilder.build();
          final output = BuildOutputBuilder();
          capturedOutput = output;
          await callback(input, output);
        };

        await ArchitectureValidator.validate([]);

        // Verify dependencies were declared.
        expect(capturedOutput.json['dependencies'], hasLength(2));

        // Verify run was called with correct args.
        final captured = verify(
          () => mockValidator.validatePackage(
            packageRoot: captureAny(named: 'packageRoot'),
            packageName: captureAny(named: 'packageName'),
            logger: any(named: 'logger'),
          ),
        ).captured;
        expect(captured[0], contains('/root'));
        expect(captured[1], 'test_pkg');
      },
    );
  });

  group('reportResults', () {
    test('writes untagged warnings', () {
      final report = ArchitectureReport(
        classes: const [],
        untagged: const ['Foo', 'Bar'],
        graph: DependencyGraph(const []),
        results: const [],
        puml: '',
      );
      final buf = StringBuffer();

      reportResults(report, Logger(buf));

      final output = buf.toString();
      expect(
        output,
        contains('${Logger.prefix} WARN: Foo has no intention annotation.'),
      );
      expect(
        output,
        contains('${Logger.prefix} WARN: Bar has no intention annotation.'),
      );
    });

    test('writes error results', () {
      final report = ArchitectureReport(
        classes: const [],
        untagged: const [],
        graph: DependencyGraph(const []),
        results: const [
          ValidationResult(severity: Severity.error, message: 'bad dep'),
        ],
        puml: '',
      );
      final buf = StringBuffer();

      reportResults(report, Logger(buf));

      expect(buf.toString(), contains('${Logger.prefix} ERROR: bad dep'));
    });

    test('writes warning results', () {
      final report = ArchitectureReport(
        classes: const [],
        untagged: const [],
        graph: DependencyGraph(const []),
        results: const [
          ValidationResult(severity: Severity.warning, message: 'hmm'),
        ],
        puml: '',
      );
      final buf = StringBuffer();

      reportResults(report, Logger(buf));

      expect(buf.toString(), contains('${Logger.prefix} WARN: hmm'));
    });

    test('writes info results', () {
      final report = ArchitectureReport(
        classes: const [],
        untagged: const [],
        graph: DependencyGraph(const []),
        results: const [
          ValidationResult(severity: Severity.info, message: 'fyi'),
        ],
        puml: '',
      );
      final buf = StringBuffer();

      reportResults(report, Logger(buf));

      expect(buf.toString(), contains('${Logger.prefix} fyi'));
    });

    test('skips ok results', () {
      final report = ArchitectureReport(
        classes: const [],
        untagged: const [],
        graph: DependencyGraph(const []),
        results: const [
          ValidationResult(severity: Severity.ok, message: 'fine'),
        ],
        puml: '',
      );
      final buf = StringBuffer();

      reportResults(report, Logger(buf));

      expect(buf.toString(), isEmpty);
    });
  });
}
