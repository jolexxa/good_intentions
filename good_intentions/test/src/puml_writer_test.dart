import 'package:good_intentions/good_intentions.dart';
import 'package:intentions_engine/intentions_engine.dart';
import 'package:test/test.dart';

void main() {
  group('PumlWriter', () {
    test('generates valid PlantUML for a simple graph', () {
      const repo = AnnotatedClass(
        name: 'UserRepo',
        intention: Intention.repository,
        dependencies: {'UserApi'},
      );
      const api = AnnotatedClass(
        name: 'UserApi',
        intention: Intention.dataSource,
        dependencies: {},
      );
      final graph = DependencyGraph([repo, api]);

      final puml = PumlWriter.write(graph, 'my_package');

      expect(puml, contains('@startuml'));
      expect(puml, contains('@enduml'));
      expect(puml, contains('package "my_package"'));
      expect(puml, contains('class UserRepo << repository >>'));
      expect(puml, contains('class UserApi << dataSource >>'));
      expect(puml, contains('UserRepo --> UserApi'));
    });

    test('omits model classes and their arrows', () {
      const user = AnnotatedClass(
        name: 'User',
        intention: Intention.model,
        dependencies: {},
      );
      const repo = AnnotatedClass(
        name: 'UserRepo',
        intention: Intention.repository,
        dependencies: {'User', 'UserApi'},
      );
      const api = AnnotatedClass(
        name: 'UserApi',
        intention: Intention.dataSource,
        dependencies: {},
      );
      final graph = DependencyGraph([user, repo, api]);

      final puml = PumlWriter.write(graph, 'pkg');

      expect(puml, isNot(contains('class User ')));
      expect(puml, isNot(contains('..>')));
      expect(puml, contains('UserRepo --> UserApi'));
    });

    test('skips unknown dependencies', () {
      const api = AnnotatedClass(
        name: 'Api',
        intention: Intention.dataSource,
        dependencies: {},
      );
      const repo = AnnotatedClass(
        name: 'Repo',
        intention: Intention.repository,
        dependencies: {'Api', 'NonExistent'},
      );
      final graph = DependencyGraph([repo, api]);

      final puml = PumlWriter.write(graph, 'pkg');

      expect(puml, contains('Repo --> Api'));
      expect(puml, isNot(contains('NonExistent')));
    });

    test('omits isolated classes with no connections', () {
      const connected = AnnotatedClass(
        name: 'Repo',
        intention: Intention.repository,
        dependencies: {'Api'},
      );
      const api = AnnotatedClass(
        name: 'Api',
        intention: Intention.dataSource,
        dependencies: {},
      );
      const isolated = AnnotatedClass(
        name: 'Lonely',
        intention: Intention.useCase,
        dependencies: {},
      );
      final graph = DependencyGraph([connected, api, isolated]);

      final puml = PumlWriter.write(graph, 'pkg');

      expect(puml, contains('class Repo << repository >>'));
      expect(puml, contains('class Api << dataSource >>'));
      expect(puml, isNot(contains('Lonely')));
    });

    test('generates empty diagram for empty graph', () {
      final graph = DependencyGraph([]);

      final puml = PumlWriter.write(graph, 'empty_pkg');

      expect(puml, contains('@startuml'));
      expect(puml, contains('@enduml'));
      expect(puml, contains('package "empty_pkg"'));
    });

    test('@partOf class is nested inside owner package', () {
      const cubit = AnnotatedClass(
        name: 'ChatCubit',
        intention: Intention.viewModel,
        dependencies: {'ChatLogic'},
      );
      const logic = AnnotatedClass(
        name: 'ChatLogic',
        intention: Intention.partOf,
        dependencies: {'Repo'},
        owner: 'ChatCubit',
      );
      const repo = AnnotatedClass(
        name: 'Repo',
        intention: Intention.repository,
        dependencies: {},
      );
      final graph = DependencyGraph([cubit, logic, repo]);

      final puml = PumlWriter.write(graph, 'pkg');

      // ChatLogic should be inside a package with ChatCubit.
      expect(puml, contains('package "ChatCubit" as _ChatCubit'));
      expect(puml, contains('class ChatLogic << viewModel >>'));
      expect(puml, contains('class ChatCubit << viewModel >>'));
      expect(puml, contains('ChatCubit +-- ChatLogic'));
      expect(puml, contains('ChatCubit --> ChatLogic'));
      expect(puml, contains('ChatLogic --> Repo'));
      // ChatLogic should be indented inside the package (4 spaces),
      // not at the top level (2 spaces).
      expect(puml, contains('    class ChatLogic << viewModel >>'));
      expect(
        puml,
        isNot(matches(RegExp('^  class ChatLogic', multiLine: true))),
        reason: 'ChatLogic should be nested, not top-level',
      );
    });

    test('@partOf with missing owner falls back to partOf stereotype', () {
      const logic = AnnotatedClass(
        name: 'Orphan',
        intention: Intention.partOf,
        dependencies: {'Repo'},
        owner: 'NonExistent',
      );
      const repo = AnnotatedClass(
        name: 'Repo',
        intention: Intention.repository,
        dependencies: {},
      );
      final graph = DependencyGraph([logic, repo]);

      final puml = PumlWriter.write(graph, 'pkg');

      // Owner missing from graph — Orphan nests under NonExistent package
      // with fallback stereotype.
      expect(puml, contains('package "NonExistent" as _NonExistent'));
      expect(puml, contains('class Orphan << partOf >>'));
    });

    test('@partOf chain flattens into root owner package', () {
      const root = AnnotatedClass(
        name: 'RootCubit',
        intention: Intention.viewModel,
        dependencies: {'Mid'},
      );
      const mid = AnnotatedClass(
        name: 'Mid',
        intention: Intention.partOf,
        dependencies: {'Leaf'},
        owner: 'RootCubit',
      );
      const leaf = AnnotatedClass(
        name: 'Leaf',
        intention: Intention.partOf,
        dependencies: {'Api'},
        owner: 'Mid',
      );
      const api = AnnotatedClass(
        name: 'Api',
        intention: Intention.dataSource,
        dependencies: {},
      );
      final graph = DependencyGraph([root, mid, leaf, api]);

      final puml = PumlWriter.write(graph, 'pkg');

      // Both Mid and Leaf should be inside RootCubit's package.
      expect(puml, contains('package "RootCubit" as _RootCubit'));
      expect(puml, contains('class Mid << viewModel >>'));
      expect(puml, contains('class Leaf << viewModel >>'));
      expect(puml, contains('RootCubit +-- Mid'));
      expect(puml, contains('RootCubit +-- Leaf'));
      // No nested packages for Mid.
      expect(puml, isNot(contains('package "Mid"')));
    });

    test('@partOf with null owner renders flat with fallback stereotype', () {
      const logic = AnnotatedClass(
        name: 'Detached',
        intention: Intention.partOf,
        dependencies: {'Api'},
      );
      const api = AnnotatedClass(
        name: 'Api',
        intention: Intention.dataSource,
        dependencies: {},
      );
      final graph = DependencyGraph([logic, api]);

      final puml = PumlWriter.write(graph, 'pkg');

      // No owner → renders flat, stereotype falls back to partOf.
      expect(puml, contains('class Detached << partOf >>'));
      // Should not have a nested package for the detached class.
      expect(
        puml,
        isNot(contains('package "Detached" as _Detached')),
      );
    });

    test('draws violation arrows in red', () {
      // dataSource depending on viewModel is an upward violation.
      const api = AnnotatedClass(
        name: 'Api',
        intention: Intention.dataSource,
        dependencies: {'Cubit'},
      );
      const cubit = AnnotatedClass(
        name: 'Cubit',
        intention: Intention.viewModel,
        dependencies: {},
      );
      final graph = DependencyGraph([api, cubit]);

      final puml = PumlWriter.write(
        graph,
        'pkg',
        validationResults: [
          const ValidationResult(
            from: 'Api',
            to: 'Cubit',
            severity: Severity.error,
            message: 'upward dependency',
          ),
        ],
      );

      expect(puml, contains('Api -[#red]-> Cubit'));
      expect(puml, isNot(contains('Api --> Cubit')));
    });

    test('handles multiple non-model dependencies', () {
      const api = AnnotatedClass(
        name: 'Api',
        intention: Intention.dataSource,
        dependencies: {},
      );
      const store = AnnotatedClass(
        name: 'Store',
        intention: Intention.dataSource,
        dependencies: {},
      );
      const repo = AnnotatedClass(
        name: 'Repo',
        intention: Intention.repository,
        dependencies: {'Api', 'Store'},
      );
      final graph = DependencyGraph([api, store, repo]);

      final puml = PumlWriter.write(graph, 'pkg');

      expect(puml, contains('Repo --> Api'));
      expect(puml, contains('Repo --> Store'));
    });
  });
}
