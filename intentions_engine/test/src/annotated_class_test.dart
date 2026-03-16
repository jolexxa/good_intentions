import 'package:intentions_engine/intentions_engine.dart';
import 'package:test/test.dart';

void main() {
  group('AnnotatedClass', () {
    test('layer delegates to intention', () {
      const repo = AnnotatedClass(
        name: 'UserRepo',
        intention: Intention.repository,
        dependencies: {},
      );
      expect(repo.layer, Layer.domain);
    });

    test('layer is null for model', () {
      const user = AnnotatedClass(
        name: 'User',
        intention: Intention.model,
        dependencies: {},
      );
      expect(user.layer, isNull);
    });

    test('layer is null for hack', () {
      const mystery = AnnotatedClass(
        name: 'Mystery',
        intention: Intention.hack,
        dependencies: {},
      );
      expect(mystery.layer, isNull);
    });

    test('layer is null for partOf', () {
      const logic = AnnotatedClass(
        name: 'Logic',
        intention: Intention.partOf,
        dependencies: {},
        owner: 'Owner',
      );
      expect(logic.layer, isNull);
      expect(logic.owner, 'Owner');
    });

    test('equality is based on name', () {
      const a = AnnotatedClass(
        name: 'Foo',
        intention: Intention.repository,
        dependencies: {'Bar'},
      );
      const b = AnnotatedClass(
        name: 'Foo',
        intention: Intention.dataSource,
        dependencies: {},
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('inequality for different names', () {
      const a = AnnotatedClass(
        name: 'Foo',
        intention: Intention.repository,
        dependencies: {},
      );
      const b = AnnotatedClass(
        name: 'Bar',
        intention: Intention.repository,
        dependencies: {},
      );
      expect(a, isNot(equals(b)));
    });

    test('toString includes name and intention', () {
      const c = AnnotatedClass(
        name: 'Foo',
        intention: Intention.repository,
        dependencies: {},
      );
      expect(c.toString(), 'AnnotatedClass(Foo, @repository)');
    });
  });
}
