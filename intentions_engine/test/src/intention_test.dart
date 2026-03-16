import 'package:intentions_engine/intentions_engine.dart';
import 'package:test/test.dart';

void main() {
  group('Intention', () {
    test('layer annotations map to correct layers', () {
      expect(Intention.view.layer, Layer.view);
      expect(Intention.viewModel.layer, Layer.viewModel);
      expect(Intention.useCase.layer, Layer.useCase);
      expect(Intention.repository.layer, Layer.domain);
      expect(Intention.dataSource.layer, Layer.data);
    });

    test('model has no layer', () {
      expect(Intention.model.layer, isNull);
      expect(Intention.model.isModel, isTrue);
      expect(Intention.model.isLayer, isFalse);
      expect(Intention.model.isHack, isFalse);
    });

    test('hack has no layer', () {
      expect(Intention.hack.layer, isNull);
      expect(Intention.hack.isHack, isTrue);
      expect(Intention.hack.isLayer, isFalse);
      expect(Intention.hack.isModel, isFalse);
    });

    test('partOf has no layer', () {
      expect(Intention.partOf.layer, isNull);
      expect(Intention.partOf.isPartOf, isTrue);
      expect(Intention.partOf.isLayer, isFalse);
      expect(Intention.partOf.isModel, isFalse);
      expect(Intention.partOf.isHack, isFalse);
    });

    test('isLayer is true for layer annotations', () {
      expect(Intention.view.isLayer, isTrue);
      expect(Intention.viewModel.isLayer, isTrue);
      expect(Intention.useCase.isLayer, isTrue);
      expect(Intention.repository.isLayer, isTrue);
      expect(Intention.dataSource.isLayer, isTrue);
    });

    group('fromAnnotationName', () {
      test('maps annotation class names correctly', () {
        expect(Intention.fromAnnotationName('View'), Intention.view);
        expect(Intention.fromAnnotationName('ViewModel'), Intention.viewModel);
        expect(Intention.fromAnnotationName('UseCase'), Intention.useCase);
        expect(
          Intention.fromAnnotationName('Repository'),
          Intention.repository,
        );
        expect(
          Intention.fromAnnotationName('DataSource'),
          Intention.dataSource,
        );
        expect(Intention.fromAnnotationName('Model'), Intention.model);
        expect(Intention.fromAnnotationName('Hack'), Intention.hack);
        expect(Intention.fromAnnotationName('PartOf'), Intention.partOf);
      });

      test('returns null for unknown names', () {
        expect(Intention.fromAnnotationName('Unknown'), isNull);
        expect(Intention.fromAnnotationName(''), isNull);
      });
    });
  });
}
