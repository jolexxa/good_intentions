import 'package:intentions_engine/intentions_engine.dart';
import 'package:test/test.dart';

void main() {
  // Helper to create an AnnotatedClass concisely.
  AnnotatedClass ac(
    String name,
    Intention intention, [
    Set<String> deps = const {},
    String? owner,
  ]) => AnnotatedClass(
    name: name,
    intention: intention,
    dependencies: deps,
    owner: owner,
  );

  group('validate', () {
    group('model (cross-cutting)', () {
      test('any layer can depend on a model', () {
        final user = ac('User', Intention.model);
        final vm = ac('UserVM', Intention.viewModel, {'User'});
        final graph = DependencyGraph([user, vm]);

        final result = validate(from: vm, to: user, graph: graph);
        expect(result.severity, Severity.ok);
      });
    });

    group('hack', () {
      test('hack source always warns', () {
        final mystery = ac('Mystery', Intention.hack, {'UserRepo'});
        final repo = ac('UserRepo', Intention.repository);
        final graph = DependencyGraph([mystery, repo]);

        final result = validate(from: mystery, to: repo, graph: graph);
        expect(result.severity, Severity.warning);
        expect(result.message, contains('@hack'));
      });

      test('hack target always warns', () {
        final vm = ac('UserVM', Intention.viewModel, {'Mystery'});
        final mystery = ac('Mystery', Intention.hack);
        final graph = DependencyGraph([vm, mystery]);

        final result = validate(from: vm, to: mystery, graph: graph);
        expect(result.severity, Severity.warning);
        expect(result.message, contains('@hack'));
      });
    });

    group('upward dependencies', () {
      test('data source depending on view model is an error', () {
        final ds = ac('Api', Intention.dataSource, {'VM'});
        final vm = ac('VM', Intention.viewModel);
        final graph = DependencyGraph([ds, vm]);

        final result = validate(from: ds, to: vm, graph: graph);
        expect(result.severity, Severity.error);
        expect(result.message, contains('upward'));
      });

      test('repository depending on use case is an error', () {
        final repo = ac('Repo', Intention.repository, {'UC'});
        final uc = ac('UC', Intention.useCase);
        final graph = DependencyGraph([repo, uc]);

        final result = validate(from: repo, to: uc, graph: graph);
        expect(result.severity, Severity.error);
      });
    });

    group('same-layer dependencies', () {
      test('two repositories depending on each other is an error', () {
        final a = ac('RepoA', Intention.repository, {'RepoB'});
        final b = ac('RepoB', Intention.repository);
        final graph = DependencyGraph([a, b]);

        final result = validate(from: a, to: b, graph: graph);
        expect(result.severity, Severity.error);
        expect(result.message, contains('sibling'));
      });
    });

    group('@partOf', () {
      test('owner can depend on its @partOf implementation detail', () {
        final logic = ac(
          'ChatLogic',
          Intention.partOf,
          const {},
          'ChatCubit',
        );
        final cubit = ac('ChatCubit', Intention.viewModel, {'ChatLogic'});
        final graph = DependencyGraph([cubit, logic]);

        final result = validate(from: cubit, to: logic, graph: graph);
        expect(result.severity, Severity.ok);
        expect(result.message, contains('implementation detail'));
      });

      test('non-owner depending on @partOf class is an error', () {
        final logic = ac(
          'ChatLogic',
          Intention.partOf,
          const {},
          'ChatCubit',
        );
        final cubit = ac('ChatCubit', Intention.viewModel, {'ChatLogic'});
        final other = ac('OtherVM', Intention.viewModel, {'ChatLogic'});
        final graph = DependencyGraph([cubit, logic, other]);

        final result = validate(from: other, to: logic, graph: graph);
        expect(result.severity, Severity.error);
        expect(result.message, contains('implementation detail'));
      });

      test('@partOf class inherits owner layer for downward validation', () {
        final logic = ac(
          'ChatLogic',
          Intention.partOf,
          {'Repo'},
          'ChatCubit',
        );
        final cubit = ac('ChatCubit', Intention.viewModel);
        final repo = ac('Repo', Intention.repository);
        final graph = DependencyGraph([cubit, logic, repo]);

        // ChatLogic is effectively viewModel → domain is skipping useCase.
        final result = validate(from: logic, to: repo, graph: graph);
        expect(result.severity, Severity.warning);
      });

      test('@partOf class inherits owner layer for upward validation', () {
        final logic = ac(
          'RepoHelper',
          Intention.partOf,
          {'UC'},
          'Repo',
        );
        final repo = ac('Repo', Intention.repository);
        final uc = ac('UC', Intention.useCase);
        final graph = DependencyGraph([repo, logic, uc]);

        // RepoHelper is effectively domain → useCase is upward.
        final result = validate(from: logic, to: uc, graph: graph);
        expect(result.severity, Severity.error);
        expect(result.message, contains('upward'));
      });

      test('@partOf with missing owner resolves to null layer', () {
        final logic = ac(
          'Orphan',
          Intention.partOf,
          const {},
          'NonExistent',
        );
        final repo = ac('Repo', Intention.repository, {'Orphan'});
        final graph = DependencyGraph([logic, repo]);

        // Owner not in graph → null layer → ok (non-layer).
        final result = validate(from: repo, to: logic, graph: graph);
        expect(result.severity, Severity.error);
        expect(result.message, contains('implementation detail'));
      });

      test('@partOf siblings (same owner) can access each other', () {
        final stateA = ac(
          'ModelState',
          Intention.partOf,
          {'DownloadSvc'},
          'ModelRepo',
        );
        final stateB = ac(
          'DownloadSvc',
          Intention.partOf,
          {'ModelState'},
          'ModelRepo',
        );
        final repo = ac('ModelRepo', Intention.repository);
        final graph = DependencyGraph([stateA, stateB, repo]);

        final result = validate(from: stateA, to: stateB, graph: graph);
        expect(result.severity, Severity.ok);
        expect(result.message, contains('siblings'));
      });

      test('@partOf sibling from different owner is blocked', () {
        final a = ac('A', Intention.partOf, {'B'}, 'OwnerX');
        final b = ac('B', Intention.partOf, const {}, 'OwnerY');
        final ownerX = ac('OwnerX', Intention.repository);
        final ownerY = ac('OwnerY', Intention.repository);
        final graph = DependencyGraph([a, b, ownerX, ownerY]);

        final result = validate(from: a, to: b, graph: graph);
        expect(result.severity, Severity.error);
        expect(result.message, contains('implementation detail'));
      });
    });

    group('dual annotations (@model @PartOf)', () {
      test('anyone can depend on @model @PartOf (model is cross-cutting)', () {
        // ModelState is @model @PartOf(ModelRepo) — intention=model, owner set.
        final state = ac('ModelState', Intention.model, const {}, 'ModelRepo');
        final cubit = ac('CardCubit', Intention.viewModel, {'ModelState'});
        final graph = DependencyGraph([state, cubit]);

        final result = validate(from: cubit, to: state, graph: graph);
        expect(result.severity, Severity.ok);
        expect(result.message, contains('cross-cutting'));
      });

      test('@model @PartOf sibling can access pure @partOf sibling', () {
        final state = ac(
          'ModelState',
          Intention.model,
          {'DownloadSvc'},
          'ModelRepo',
        );
        final svc = ac(
          'DownloadSvc',
          Intention.partOf,
          const {},
          'ModelRepo',
        );
        final repo = ac('ModelRepo', Intention.repository);
        final graph = DependencyGraph([state, svc, repo]);

        final result = validate(from: state, to: svc, graph: graph);
        expect(result.severity, Severity.ok);
        expect(result.message, contains('siblings'));
      });
    });

    group('adjacent downward', () {
      test('view model depending on use case is ok', () {
        final vm = ac('VM', Intention.viewModel, {'UC'});
        final uc = ac('UC', Intention.useCase);
        final graph = DependencyGraph([vm, uc]);

        final result = validate(from: vm, to: uc, graph: graph);
        expect(result.severity, Severity.ok);
      });

      test('use case depending on repository is ok', () {
        final uc = ac('UC', Intention.useCase, {'Repo'});
        final repo = ac('Repo', Intention.repository);
        final graph = DependencyGraph([uc, repo]);

        final result = validate(from: uc, to: repo, graph: graph);
        expect(result.severity, Severity.ok);
      });
    });

    group('skipping layers', () {
      test('info when no intermediate class wraps the target', () {
        final vm = ac('VM', Intention.viewModel, {'Api'});
        final api = ac('Api', Intention.dataSource);
        final graph = DependencyGraph([vm, api]);

        final result = validate(from: vm, to: api, graph: graph);
        expect(result.severity, Severity.warning);
        expect(result.message, contains('skipping useCase, domain'));
        expect(result.message, contains('no intermediate class'));
      });

      test('info when view skips to repository with no wrapper', () {
        final v = ac('MyView', Intention.view, {'Repo'});
        final repo = ac('Repo', Intention.repository);
        final graph = DependencyGraph([v, repo]);

        final result = validate(from: v, to: repo, graph: graph);
        expect(result.severity, Severity.warning);
        expect(result.message, contains('skipping viewModel, useCase'));
      });

      test('info when intermediate class exists but does not wrap target', () {
        final vm = ac('VM', Intention.viewModel, {'Api'});
        final uc = ac('UC', Intention.useCase); // no dep on Api
        final api = ac('Api', Intention.dataSource);
        final graph = DependencyGraph([vm, uc, api]);

        final result = validate(from: vm, to: api, graph: graph);
        expect(result.severity, Severity.warning);
      });

      test('error via claiming when intermediate wraps target', () {
        // When UC depends on Api, claiming kicks in — UC claims Api.
        // VM→Api is an error because Api is claimed by the useCase layer.
        final vm = ac('VM', Intention.viewModel, {'Api'});
        final uc = ac('UC', Intention.useCase, {'Api'});
        final api = ac('Api', Intention.dataSource);
        final graph = DependencyGraph([vm, uc, api]);

        final result = validate(from: vm, to: api, graph: graph);
        expect(result.severity, Severity.error);
        expect(result.message, contains('claimed'));
      });
    });

    group('progressive enforcement (claiming)', () {
      test('view model to claimed data source is an error', () {
        final api = ac('Api', Intention.dataSource);
        final repo = ac('Repo', Intention.repository, {'Api'});
        final vm = ac('VM', Intention.viewModel, {'Api'});
        final graph = DependencyGraph([api, repo, vm]);

        final result = validate(from: vm, to: api, graph: graph);
        expect(result.severity, Severity.error);
        expect(result.message, contains('claimed'));
      });

      test('view model to unclaimed data source is info', () {
        final apiA = ac('ApiA', Intention.dataSource);
        final apiB = ac('ApiB', Intention.dataSource);
        final repo = ac('Repo', Intention.repository, {'ApiA'});
        final vm = ac('VM', Intention.viewModel, {'ApiB'});
        final graph = DependencyGraph([apiA, apiB, repo, vm]);

        final result = validate(from: vm, to: apiB, graph: graph);
        expect(result.severity, Severity.warning);
      });

      test('use case claiming repository blocks view model', () {
        final repo = ac('Repo', Intention.repository);
        final uc = ac('GetUser', Intention.useCase, {'Repo'});
        final vm = ac('VM', Intention.viewModel, {'Repo'});
        final graph = DependencyGraph([repo, uc, vm]);

        final result = validate(from: vm, to: repo, graph: graph);
        expect(result.severity, Severity.error);
        expect(result.message, contains('claimed'));
      });

      test('view model accessing use case that claimed repo is ok', () {
        final repo = ac('Repo', Intention.repository);
        final uc = ac('GetUser', Intention.useCase, {'Repo'});
        final vm = ac('VM', Intention.viewModel, {'GetUser'});
        final graph = DependencyGraph([repo, uc, vm]);

        final result = validate(from: vm, to: uc, graph: graph);
        expect(result.severity, Severity.ok);
      });

      test('view above claiming layer still cannot bypass it', () {
        final api = ac('Api', Intention.dataSource);
        final repo = ac('Repo', Intention.repository, {'Api'});
        final v = ac('MyView', Intention.view, {'Api'});
        final graph = DependencyGraph([api, repo, v]);

        // Api is claimed by domain (repo). Even though view is above
        // domain, it must go through the claiming layer — not bypass it.
        final result = validate(from: v, to: api, graph: graph);
        expect(result.severity, Severity.error);
        expect(result.message, contains('claimed'));
      });

      test('claiming layer itself can access its claimed target', () {
        final api = ac('Api', Intention.dataSource);
        final repo = ac('Repo', Intention.repository, {'Api'});
        final otherRepo = ac('OtherRepo', Intention.repository, {'Api'});
        final graph = DependencyGraph([api, repo, otherRepo]);

        // Both repos are at the domain layer, which claims Api.
        // OtherRepo should be able to access Api since it's at the
        // claiming layer.
        final result = validate(from: otherRepo, to: api, graph: graph);
        expect(result.severity, Severity.ok);
      });
    });

    group('non-layer to non-layer', () {
      test('model depending on model is ok', () {
        final a = ac('Address', Intention.model);
        final b = ac('User', Intention.model, {'Address'});
        final graph = DependencyGraph([a, b]);

        final result = validate(from: b, to: a, graph: graph);
        expect(result.severity, Severity.ok);
      });

      test('partOf with missing owner has null layer and is ok', () {
        // Orphan has @partOf(NonExistent) but NonExistent isn't in the graph,
        // so its effective layer is null. Target is a concrete @repository.
        // Since orphan has no owner match for repo (partOf check doesn't
        // trigger because orphan is `from`, not `to`), this hits the
        // null-layer early return.
        final orphan = ac('Orphan', Intention.partOf, {'Repo'}, 'NonExistent');
        final repo = ac('Repo', Intention.repository, {'Orphan'});
        final graph = DependencyGraph([orphan, repo]);

        final result = validate(from: orphan, to: repo, graph: graph);
        expect(result.severity, Severity.ok);
        expect(result.message, contains('Non-layer'));
      });
    });

    group('ValidationResult', () {
      test('toString includes severity and message', () {
        const result = ValidationResult(
          severity: Severity.error,
          message: 'bad',
        );
        expect(result.toString(), 'ValidationResult(error: bad)');
      });
    });
  });
}
