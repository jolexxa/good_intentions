import 'package:intentions/intentions.dart';
import 'package:test/test.dart';

void main() {
  group('annotations', () {
    test('const instances are the correct types', () {
      expect(view, isA<View>());
      expect(viewModel, isA<ViewModel>());
      expect(repository, isA<Repository>());
      expect(useCase, isA<UseCase>());
      expect(model, isA<Model>());
      expect(dataSource, isA<DataSource>());
      expect(hack, isA<Hack>());
    });

    test('classes can be const-constructed', () {
      const v = View();
      const vm = ViewModel();
      const r = Repository();
      const uc = UseCase();
      const m = Model();
      const ds = DataSource();
      const h = Hack();
      const po = PartOf(Object);

      expect(v, isA<View>());
      expect(vm, isA<ViewModel>());
      expect(r, isA<Repository>());
      expect(uc, isA<UseCase>());
      expect(m, isA<Model>());
      expect(ds, isA<DataSource>());
      expect(h, isA<Hack>());
      expect(po, isA<PartOf>());
      expect(po.owner, Object);
    });
  });
}
