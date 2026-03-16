import 'package:intentions_engine/intentions_engine.dart';
import 'package:test/test.dart';

void main() {
  group('DependencyGraph', () {
    test('lookup by name', () {
      const repo = AnnotatedClass(
        name: 'UserRepo',
        intention: Intention.repository,
        dependencies: {},
      );
      final graph = DependencyGraph([repo]);

      expect(graph['UserRepo'], repo);
      expect(graph['Nope'], isNull);
    });

    test('classes returns all entries', () {
      final classes = [
        const AnnotatedClass(
          name: 'A',
          intention: Intention.view,
          dependencies: {},
        ),
        const AnnotatedClass(
          name: 'B',
          intention: Intention.repository,
          dependencies: {},
        ),
      ];
      final graph = DependencyGraph(classes);

      expect(graph.classes, hasLength(2));
    });

    group('claimedClasses', () {
      test('repository claiming a data source', () {
        const api = AnnotatedClass(
          name: 'UserApi',
          intention: Intention.dataSource,
          dependencies: {},
        );
        const repo = AnnotatedClass(
          name: 'UserRepo',
          intention: Intention.repository,
          dependencies: {'UserApi'},
        );
        final graph = DependencyGraph([api, repo]);

        final claimed = graph.claimedClasses();
        expect(claimed, hasLength(1));

        final claim = claimed.first;
        expect(claim.annotatedClass, api);
        expect(claim.claimedByLayer, Layer.domain);
      });

      test('highest claimer wins', () {
        const api = AnnotatedClass(
          name: 'UserApi',
          intention: Intention.dataSource,
          dependencies: {},
        );
        const repo = AnnotatedClass(
          name: 'UserRepo',
          intention: Intention.repository,
          dependencies: {'UserApi'},
        );
        const uc = AnnotatedClass(
          name: 'GetUser',
          intention: Intention.useCase,
          dependencies: {'UserApi'},
        );
        final graph = DependencyGraph([api, repo, uc]);

        final claimed = graph.claimedClasses();
        expect(claimed, hasLength(1));

        final claim = claimed.first;
        expect(claim.annotatedClass, api);
        expect(claim.claimedByLayer, Layer.useCase);
      });

      test('unclaimed classes produce empty set', () {
        const api = AnnotatedClass(
          name: 'UserApi',
          intention: Intention.dataSource,
          dependencies: {},
        );
        final graph = DependencyGraph([api]);

        expect(graph.claimedClasses(), isEmpty);
      });

      test('model dependencies do not produce claims', () {
        const user = AnnotatedClass(
          name: 'User',
          intention: Intention.model,
          dependencies: {},
        );
        const repo = AnnotatedClass(
          name: 'UserRepo',
          intention: Intention.repository,
          dependencies: {'User'},
        );
        final graph = DependencyGraph([user, repo]);

        expect(graph.claimedClasses(), isEmpty);
      });

      test('hack dependencies do not produce claims', () {
        const mystery = AnnotatedClass(
          name: 'Mystery',
          intention: Intention.hack,
          dependencies: {},
        );
        const repo = AnnotatedClass(
          name: 'Repo',
          intention: Intention.repository,
          dependencies: {'Mystery'},
        );
        final graph = DependencyGraph([mystery, repo]);

        expect(graph.claimedClasses(), isEmpty);
      });

      test('dependencies on unknown classes are ignored', () {
        const repo = AnnotatedClass(
          name: 'Repo',
          intention: Intention.repository,
          dependencies: {'NonExistent'},
        );
        final graph = DependencyGraph([repo]);

        expect(graph.claimedClasses(), isEmpty);
      });

      test('same-layer dependencies do not produce claims', () {
        const apiA = AnnotatedClass(
          name: 'ApiA',
          intention: Intention.dataSource,
          dependencies: {},
        );
        const apiB = AnnotatedClass(
          name: 'ApiB',
          intention: Intention.dataSource,
          dependencies: {'ApiA'},
        );
        final graph = DependencyGraph([apiA, apiB]);

        expect(graph.claimedClasses(), isEmpty);
      });

      test('@partOf class uses effective layer for claiming', () {
        const api = AnnotatedClass(
          name: 'Api',
          intention: Intention.dataSource,
          dependencies: {},
        );
        const cubit = AnnotatedClass(
          name: 'Cubit',
          intention: Intention.viewModel,
          dependencies: {'Logic'},
        );
        const logic = AnnotatedClass(
          name: 'Logic',
          intention: Intention.partOf,
          dependencies: {'Api'},
          owner: 'Cubit',
        );
        final graph = DependencyGraph([api, cubit, logic]);

        // Logic is effectively viewModel, so it claims Api at viewModel.
        final claimed = graph.claimedClasses();
        expect(claimed, hasLength(1));
        expect(claimed.first.annotatedClass, api);
        expect(claimed.first.claimedByLayer, Layer.viewModel);
      });

      test('excluding removes a class from claim computation', () {
        const api = AnnotatedClass(
          name: 'Api',
          intention: Intention.dataSource,
          dependencies: {},
        );
        const repo = AnnotatedClass(
          name: 'Repo',
          intention: Intention.repository,
          dependencies: {'Api'},
        );
        const vm = AnnotatedClass(
          name: 'VM',
          intention: Intention.viewModel,
          dependencies: {'Api'},
        );
        final graph = DependencyGraph([api, repo, vm]);

        // Without excluding, highest claimer is viewModel (VM).
        final allClaims = graph.claimedClasses();
        expect(allClaims.first.claimedByLayer, Layer.viewModel);

        // Excluding VM, the claimer is domain (Repo).
        final withoutVm = graph.claimedClasses(excluding: vm);
        expect(withoutVm.first.claimedByLayer, Layer.domain);
      });
    });
  });

  group('effectiveLayer', () {
    test('returns layer directly for non-partOf classes', () {
      const repo = AnnotatedClass(
        name: 'Repo',
        intention: Intention.repository,
        dependencies: {},
      );
      final graph = DependencyGraph([repo]);

      expect(effectiveLayer(repo, graph), Layer.domain);
    });

    test('resolves owner layer for @partOf classes', () {
      const cubit = AnnotatedClass(
        name: 'ChatCubit',
        intention: Intention.viewModel,
        dependencies: {'ChatLogic'},
      );
      const logic = AnnotatedClass(
        name: 'ChatLogic',
        intention: Intention.partOf,
        dependencies: {},
        owner: 'ChatCubit',
      );
      final graph = DependencyGraph([cubit, logic]);

      expect(effectiveLayer(logic, graph), Layer.viewModel);
    });

    test('returns null when owner is missing from graph', () {
      const logic = AnnotatedClass(
        name: 'Orphan',
        intention: Intention.partOf,
        dependencies: {},
        owner: 'NonExistent',
      );
      final graph = DependencyGraph([logic]);

      expect(effectiveLayer(logic, graph), isNull);
    });

    test('follows chained @partOf references', () {
      const cubit = AnnotatedClass(
        name: 'Cubit',
        intention: Intention.viewModel,
        dependencies: {'Helper'},
      );
      const helper = AnnotatedClass(
        name: 'Helper',
        intention: Intention.partOf,
        dependencies: {'Inner'},
        owner: 'Cubit',
      );
      const inner = AnnotatedClass(
        name: 'Inner',
        intention: Intention.partOf,
        dependencies: {},
        owner: 'Helper',
      );
      final graph = DependencyGraph([cubit, helper, inner]);

      expect(effectiveLayer(inner, graph), Layer.viewModel);
    });

    test('returns null for model (no layer, no owner)', () {
      const user = AnnotatedClass(
        name: 'User',
        intention: Intention.model,
        dependencies: {},
      );
      final graph = DependencyGraph([user]);

      expect(effectiveLayer(user, graph), isNull);
    });
  });

  group('ClaimedClass', () {
    test('equality is based on annotated class', () {
      const ac = AnnotatedClass(
        name: 'Foo',
        intention: Intention.dataSource,
        dependencies: {},
      );
      const a = ClaimedClass(ac, Layer.domain);
      const b = ClaimedClass(ac, Layer.useCase);

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('toString includes name and claiming layer', () {
      const ac = AnnotatedClass(
        name: 'Foo',
        intention: Intention.dataSource,
        dependencies: {},
      );
      const claim = ClaimedClass(ac, Layer.domain);
      expect(claim.toString(), 'ClaimedClass(Foo, by domain)');
    });
  });
}
