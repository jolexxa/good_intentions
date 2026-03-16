import 'package:intentions_engine/intentions_engine.dart';
import 'package:test/test.dart';

void main() {
  group('Layer', () {
    test('ordering is view > viewModel > useCase > domain > data', () {
      expect(Layer.view.index, lessThan(Layer.viewModel.index));
      expect(Layer.viewModel.index, lessThan(Layer.useCase.index));
      expect(Layer.useCase.index, lessThan(Layer.domain.index));
      expect(Layer.domain.index, lessThan(Layer.data.index));
    });

    test('isAbove returns true for higher layers', () {
      expect(Layer.view.isAbove(Layer.data), isTrue);
      expect(Layer.view.isAbove(Layer.viewModel), isTrue);
      expect(Layer.useCase.isAbove(Layer.domain), isTrue);
    });

    test('isAbove returns false for same or lower layers', () {
      expect(Layer.view.isAbove(Layer.view), isFalse);
      expect(Layer.data.isAbove(Layer.view), isFalse);
      expect(Layer.domain.isAbove(Layer.useCase), isFalse);
    });

    test('isBelow returns true for lower layers', () {
      expect(Layer.data.isBelow(Layer.view), isTrue);
      expect(Layer.domain.isBelow(Layer.useCase), isTrue);
    });

    test('isBelow returns false for same or higher layers', () {
      expect(Layer.view.isBelow(Layer.view), isFalse);
      expect(Layer.view.isBelow(Layer.data), isFalse);
    });

    test('compareTo orders correctly', () {
      final sorted = [Layer.data, Layer.view, Layer.useCase]..sort();
      expect(sorted, [Layer.view, Layer.useCase, Layer.data]);
    });
  });
}
