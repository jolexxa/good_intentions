import 'package:build/build.dart';
import 'package:build_test/build_test.dart';
import 'package:good_intentions/good_intentions.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

const _root = 'good_intentions';

void main() {
  group('IntentionsBuilder', () {
    test('buildExtensions maps package to puml', () {
      final builder = IntentionsBuilder();

      expect(
        builder.buildExtensions,
        equals({
          r'$package$': ['lib/architecture.g.puml'],
        }),
      );
    });

    test('generates puml for annotated classes', () async {
      final result = await testBuilderWithDeps(
        IntentionsBuilder(),
        {
          '$_root|lib/_fixture/user_repo.dart':
              '''
import 'package:intentions/intentions.dart';
import 'package:$_root/_fixture/user_api.dart';

@repository
class UserRepo {
  const UserRepo(this.api);
  final UserApi api;
}
''',
          '$_root|lib/_fixture/user_api.dart': '''
import 'package:intentions/intentions.dart';

@dataSource
class UserApi {
  const UserApi();
}
''',
        },
        rootPackage: _root,
      );

      final puml = result.readerWriter.testing.readString(
        makeAssetId('$_root|lib/architecture.g.puml'),
      );
      expect(puml, contains('@startuml'));
      expect(puml, contains('@enduml'));
      expect(puml, contains('package "$_root"'));
      expect(puml, contains('class UserRepo << repository >>'));
      expect(puml, contains('class UserApi << dataSource >>'));
      expect(puml, contains('UserRepo --> UserApi'));
    });

    test('omits model classes and their arrows from diagram', () async {
      final result = await testBuilderWithDeps(
        IntentionsBuilder(),
        {
          '$_root|lib/_fixture/user.dart': '''
import 'package:intentions/intentions.dart';

@model
class User {
  const User();
}
''',
          '$_root|lib/_fixture/user_api.dart': '''
import 'package:intentions/intentions.dart';

@dataSource
class UserApi {
  const UserApi();
}
''',
          '$_root|lib/_fixture/user_repo.dart':
              '''
import 'package:intentions/intentions.dart';
import 'package:$_root/_fixture/user.dart';
import 'package:$_root/_fixture/user_api.dart';

@repository
class UserRepo {
  const UserRepo(this.user, this.api);
  final User user;
  final UserApi api;
}
''',
        },
        rootPackage: _root,
      );

      final puml = result.readerWriter.testing.readString(
        makeAssetId('$_root|lib/architecture.g.puml'),
      );
      expect(puml, isNot(contains('class User ')));
      expect(puml, isNot(contains('..>')));
      expect(puml, contains('UserRepo --> UserApi'));
    });

    test('skips private and unannotated classes from diagram', () async {
      final logs = <LogRecord>[];
      final result = await testBuilderWithDeps(
        IntentionsBuilder(),
        {
          '$_root|lib/_fixture/stuff.dart': '''
import 'package:intentions/intentions.dart';
import 'package:$_root/_fixture/api.dart';

@repository
class PublicRepo {
  const PublicRepo(this.api);
  final PublicApi api;
}

class _PrivateHelper {
  const _PrivateHelper();
}

class UnannotatedThing {
  const UnannotatedThing();
}
''',
          '$_root|lib/_fixture/api.dart': '''
import 'package:intentions/intentions.dart';

@dataSource
class PublicApi {
  const PublicApi();
}
''',
        },
        rootPackage: _root,
        onLog: logs.add,
      );

      final puml = result.readerWriter.testing.readString(
        makeAssetId('$_root|lib/architecture.g.puml'),
      );
      expect(puml, contains('class PublicRepo << repository >>'));
      expect(puml, isNot(contains('_PrivateHelper')));
      expect(puml, isNot(contains('UnannotatedThing')));

      final warnings = logs
          .where((r) => r.level == Level.WARNING)
          .map((r) => r.message)
          .toList();
      expect(
        warnings,
        anyElement(
          contains(
            'UnannotatedThing is a public concrete class '
            'with no intention annotation.',
          ),
        ),
      );
    });

    test('discovers annotated classes from dependency packages', () async {
      // ValidationReporter is @useCase in good_intentions.
      // Phase 1 discovers it via constructor param scanning.
      final result = await testBuilderWithDeps(
        IntentionsBuilder(),
        {
          '$_root|lib/_fixture/graph_service.dart': '''
import 'package:intentions/intentions.dart';
import 'package:good_intentions/good_intentions.dart';

@repository
class GraphService {
  const GraphService(this.reporter);
  final ValidationReporter reporter;
}
''',
        },
        rootPackage: _root,
      );

      final puml = result.readerWriter.testing.readString(
        makeAssetId('$_root|lib/architecture.g.puml'),
      );
      expect(puml, contains('class GraphService << repository >>'));
      expect(puml, contains('class ValidationReporter << useCase >>'));
      expect(puml, contains('GraphService -[#red]-> ValidationReporter'));
    });

    test('local classes take priority over external discoveries', () async {
      final result = await testBuilderWithDeps(
        IntentionsBuilder(),
        {
          '$_root|lib/_fixture/local_graph.dart': '''
import 'package:intentions/intentions.dart';

@repository
class DependencyGraph {
  const DependencyGraph();
}
''',
          '$_root|lib/_fixture/graph_user.dart': '''
import 'package:intentions/intentions.dart';
import 'package:intentions_engine/intentions_engine.dart';

@useCase
class GraphUser {
  const GraphUser(this.graph);
  final DependencyGraph graph;
}
''',
        },
        rootPackage: _root,
      );

      final puml = result.readerWriter.testing.readString(
        makeAssetId('$_root|lib/architecture.g.puml'),
      );
      // Local definition wins — it's @repository, not @model
      // from intentions_engine
      expect(puml, contains('class DependencyGraph << repository >>'));
    });

    test('extracts dependencies from generic type arguments', () async {
      final result = await testBuilderWithDeps(
        IntentionsBuilder(),
        {
          '$_root|lib/_fixture/api.dart': '''
import 'package:intentions/intentions.dart';

@dataSource
class ConfigApi {
  const ConfigApi();
}
''',
          '$_root|lib/_fixture/catalog.dart': '''
import 'package:intentions/intentions.dart';
import 'package:$_root/_fixture/api.dart';

@repository
class ModelCatalog {
  const ModelCatalog(this.apis);
  final Map<String, ConfigApi> apis;
}
''',
        },
        rootPackage: _root,
      );

      final puml = result.readerWriter.testing.readString(
        makeAssetId('$_root|lib/architecture.g.puml'),
      );
      expect(puml, contains('class ConfigApi << dataSource >>'));
      expect(puml, contains('class ModelCatalog << repository >>'));
      expect(puml, contains('ModelCatalog --> ConfigApi'));
    });

    test('extracts dependencies from instance fields', () async {
      final result = await testBuilderWithDeps(
        IntentionsBuilder(),
        {
          '$_root|lib/_fixture/logger.dart': '''
import 'package:intentions/intentions.dart';

@dataSource
class CowLogger {
  const CowLogger();
}
''',
          '$_root|lib/_fixture/service.dart': '''
import 'package:intentions/intentions.dart';
import 'package:$_root/_fixture/logger.dart';

@repository
class MyService {
  MyService();
  late final CowLogger logger;
}
''',
        },
        rootPackage: _root,
      );

      final puml = result.readerWriter.testing.readString(
        makeAssetId('$_root|lib/architecture.g.puml'),
      );
      expect(puml, contains('class CowLogger << dataSource >>'));
      expect(puml, contains('class MyService << repository >>'));
      expect(puml, contains('MyService --> CowLogger'));
    });

    test('discovers dependency-package classes via transitive imports',
        () async {
      // The fixture imports good_intentions and uses
      // ValidationReporter. Phase 2 walks transitive imports and discovers
      // other annotated non-model classes like ClassCollector and
      // IntentionsBuilder from the same package.
      final result = await testBuilderWithDeps(
        IntentionsBuilder(),
        {
          '$_root|lib/_fixture/importer.dart': '''
import 'package:intentions/intentions.dart';
import 'package:good_intentions/good_intentions.dart';

@repository
class Importer {
  const Importer(this.reporter);
  final ValidationReporter reporter;
}
''',
        },
        rootPackage: _root,
      );

      final puml = result.readerWriter.testing.readString(
        makeAssetId('$_root|lib/architecture.g.puml'),
      );
      expect(puml, contains('class Importer << repository >>'));
      expect(puml, contains('class ValidationReporter << useCase >>'));
      expect(puml, contains('Importer -[#red]-> ValidationReporter'));
    });

    test('extracts @PartOf annotation with owner and resolves stereotype',
        () async {
      final result = await testBuilderWithDeps(
        IntentionsBuilder(),
        {
          '$_root|lib/_fixture/cubit.dart': '''
import 'package:intentions/intentions.dart';
import 'package:$_root/_fixture/logic.dart';

@viewModel
class MyCubit {
  const MyCubit(this.logic);
  final MyLogic logic;
}
''',
          '$_root|lib/_fixture/logic.dart': '''
import 'package:intentions/intentions.dart';
import 'package:$_root/_fixture/cubit.dart';
import 'package:$_root/_fixture/repo.dart';

@PartOf(MyCubit)
class MyLogic {
  const MyLogic(this.repo);
  final MyRepo repo;
}
''',
          '$_root|lib/_fixture/repo.dart': '''
import 'package:intentions/intentions.dart';

@repository
class MyRepo {
  const MyRepo();
}
''',
        },
        rootPackage: _root,
      );

      final puml = result.readerWriter.testing.readString(
        makeAssetId('$_root|lib/architecture.g.puml'),
      );
      // @PartOf should resolve to owner's intention in stereotype.
      expect(puml, contains('class MyLogic << viewModel >>'));
      expect(puml, contains('class MyCubit << viewModel >>'));
      expect(puml, contains('MyCubit --> MyLogic'));
      expect(puml, contains('MyLogic --> MyRepo'));
    });

    test('extracts dual @repository @PartOf annotation correctly', () async {
      final result = await testBuilderWithDeps(
        IntentionsBuilder(),
        {
          '$_root|lib/_fixture/owner.dart': '''
import 'package:intentions/intentions.dart';
import 'package:$_root/_fixture/helper.dart';

@useCase
class MyOwner {
  const MyOwner(this.helper);
  final MyHelper helper;
}
''',
          '$_root|lib/_fixture/helper.dart': '''
import 'package:intentions/intentions.dart';
import 'package:$_root/_fixture/owner.dart';

@repository
@PartOf(MyOwner)
class MyHelper {
  const MyHelper();
}
''',
        },
        rootPackage: _root,
      );

      final puml = result.readerWriter.testing.readString(
        makeAssetId('$_root|lib/architecture.g.puml'),
      );
      // Dual annotation: primary is @repository, so stereotype is repository.
      expect(puml, contains('class MyHelper << repository >>'));
      expect(puml, contains('class MyOwner << useCase >>'));
      expect(puml, contains('MyOwner --> MyHelper'));
    });

    test('skips hosted dependency packages', () async {
      final logs = <LogRecord>[];
      // The fixture imports `package:meta/meta.dart` which is a hosted
      // package (lives in .pub-cache). Classes from hosted packages should
      // not be scanned or produce warnings.
      await testBuilderWithDeps(
        IntentionsBuilder(),
        {
          '$_root|lib/_fixture/uses_meta.dart': '''
import 'package:intentions/intentions.dart';
import 'package:meta/meta.dart';

@repository
class MetaUser {
  const MetaUser();
}
''',
        },
        rootPackage: _root,
        onLog: logs.add,
      );

      // No warnings about unannotated classes from the meta package.
      final warnings = logs
          .where((r) => r.level == Level.WARNING)
          .map((r) => r.message)
          .toList();
      expect(warnings, isEmpty);
    });

    test('does not warn for abstract or interface classes', () async {
      final logs = <LogRecord>[];
      await testBuilderWithDeps(
        IntentionsBuilder(),
        {
          '$_root|lib/_fixture/abstracts.dart': '''
abstract class AbstractThing {}

interface class InterfaceThing {}

abstract interface class PureInterface {}
''',
        },
        rootPackage: _root,
        onLog: logs.add,
      );

      final warnings = logs
          .where((r) => r.level == Level.WARNING)
          .map((r) => r.message)
          .toList();
      expect(warnings, isEmpty);
    });

    test('generates empty diagram when no annotated classes', () async {
      final logs = <LogRecord>[];
      final result = await testBuilderWithDeps(
        IntentionsBuilder(),
        {
          '$_root|lib/_fixture/plain.dart': '''
class JustAClass {
  const JustAClass();
}
''',
        },
        rootPackage: _root,
        onLog: logs.add,
      );

      final puml = result.readerWriter.testing.readString(
        makeAssetId('$_root|lib/architecture.g.puml'),
      );
      expect(puml, contains('@startuml'));
      expect(puml, contains('@enduml'));
      expect(puml, contains('package "$_root"'));

      final warnings = logs
          .where((r) => r.level == Level.WARNING)
          .map((r) => r.message)
          .toList();
      expect(
        warnings,
        anyElement(
          contains(
            'JustAClass is a public concrete class '
            'with no intention annotation.',
          ),
        ),
      );
    });
  });

  group('intentionsBuilder factory', () {
    test('returns an IntentionsBuilder', () {
      final builder = intentionsBuilder(BuilderOptions.empty);

      expect(builder, isA<IntentionsBuilder>());
    });
  });
}
