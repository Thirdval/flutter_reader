import 'package:flutter_reader/flutter_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ItemRegistry<int> registryOf(List<double> heights) => ItemRegistry<int>.build(
    items: [
      for (var i = 0; i < heights.length; i++)
        ReaderItem<int>(id: 'i$i', typeKey: 'h${heights[i]}', data: i),
    ],
    typeConfigs: {
      for (final h in heights)
        'h$h': ItemTypeConfig<int>(typeName: 'h$h', defaultHeight: h),
    },
    initialWidth: 400,
  );

  group('ForwardLayoutModel', () {
    final model = ForwardLayoutModel<int>(registryOf([10, 20, 30]));

    test('is the identity', () {
      expect(model.itemCount, 3);
      expect(model.totalExtent, 60);
      expect([for (var i = 0; i < 3; i++) model.offsetAt(i)], [0, 10, 30]);
      expect([for (var i = 0; i < 3; i++) model.extentAt(i)], [10, 20, 30]);
      expect(model.idAt(2), 'i2');
      expect(model.indexOfId('i1'), 1);
      expect(model.dataIndexOf(2), 2);
      expect(model.rawIndexOf(1), 1);
    });

    test('indexAtOffset clamps', () {
      expect(model.indexAtOffset(-5), 0);
      expect(model.indexAtOffset(0), 0);
      expect(model.indexAtOffset(9.9), 0);
      expect(model.indexAtOffset(10), 1);
      expect(model.indexAtOffset(59.9), 2);
      expect(model.indexAtOffset(60), 2);
      expect(model.indexAtOffset(999), 2);
    });
  });

  group('ReverseLayoutModel', () {
    final model = ReverseLayoutModel<int>(registryOf([10, 20, 30]));

    test('flips indices and mirrors offsets from the end', () {
      expect(model.itemCount, 3);
      expect(model.totalExtent, 60);
      expect([for (var i = 0; i < 3; i++) model.extentAt(i)], [30, 20, 10]);
      expect([for (var i = 0; i < 3; i++) model.offsetAt(i)], [0, 30, 50]);
      expect(model.idAt(0), 'i2');
      expect(model.indexOfId('i2'), 0);
      expect(model.indexOfId('i0'), 2);
      expect(model.dataIndexOf(0), 2);
      expect(model.rawIndexOf(0), 2);
    });

    test('indexAtOffset follows the raw ranges', () {
      expect(model.indexAtOffset(-5), 0);
      expect(model.indexAtOffset(0), 0);
      expect(model.indexAtOffset(29.9), 0);
      expect(model.indexAtOffset(30), 1);
      expect(model.indexAtOffset(49.9), 1);
      expect(model.indexAtOffset(50), 2);
      expect(model.indexAtOffset(59.9), 2);
      expect(model.indexAtOffset(60), 2);
      expect(model.indexAtOffset(999), 2);
    });

    test('reportExtent lands on the data item', () {
      final registry = registryOf([10, 20, 30]);
      ReverseLayoutModel<int>(registry).reportExtent(0, 33);
      expect(registry.heightAt(2), 33);
      expect(registry.heightEntryAt(2).tier, HeightTier.measured);
    });

    test('empty registry', () {
      final model = ReverseLayoutModel<int>(registryOf([]));
      expect(model.itemCount, 0);
      expect(model.indexAtOffset(0), -1);
    });
  });
}
