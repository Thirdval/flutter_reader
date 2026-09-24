import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reader/flutter_reader.dart';

void main() {
  final typeConfigs = {
    'text': const ItemTypeConfig<Object?>(
      typeName: 'text',
      defaultHeight: 48.0,
      defaultConfidence: 0.3,
      widthSensitivity: WidthSensitivity.dependent,
    ),
    'header': const ItemTypeConfig<Object?>(
      typeName: 'header',
      defaultHeight: 36.0,
      defaultConfidence: 0.9,
      widthSensitivity: WidthSensitivity.invariant,
    ),
    'image': ItemTypeConfig<Object?>(
      typeName: 'image',
      defaultHeight: 200.0,
      widthSensitivity: WidthSensitivity.proportional,
      proportionalHeightFn: (data, width) {
        final aspectRatio = (data as Map)['aspectRatio'] as double;
        return width / aspectRatio;
      },
    ),
  };

  List<ReaderItem<Object?>> buildItems(int count) {
    return List.generate(
      count,
      (i) => ReaderItem<Object?>(
        id: 'item_$i',
        typeKey: i % 10 == 0 ? 'header' : 'text',
        data: null,
      ),
    );
  }

  group('ItemRegistry — construction', () {
    test('build and basic queries', () {
      final items = buildItems(100);
      final registry = ItemRegistry<Object?>.build(
        items: items,
        typeConfigs: typeConfigs,
        initialWidth: 390,
        bucketSize: 16,
      );

      expect(registry.itemCount, 100);
      expect(registry.currentWidth, 390);
    });

    test('ID → index lookup', () {
      final items = buildItems(100);
      final registry = ItemRegistry<Object?>.build(
        items: items,
        typeConfigs: typeConfigs,
        initialWidth: 390,
      );

      expect(registry.indexOfId('item_0'), 0);
      expect(registry.indexOfId('item_99'), 99);
      expect(registry.indexOfId('nonexistent'), isNull);
    });

    test('offset by ID matches offset by index', () {
      final items = buildItems(100);
      final registry = ItemRegistry<Object?>.build(
        items: items,
        typeConfigs: typeConfigs,
        initialWidth: 390,
      );

      for (final id in ['item_0', 'item_50', 'item_99']) {
        final idx = registry.indexOfId(id)!;
        expect(registry.offsetOfId(id), registry.offsetOfIndex(idx));
      }
    });

    test('nonexistent ID returns null offset', () {
      final items = buildItems(10);
      final registry = ItemRegistry<Object?>.build(
        items: items,
        typeConfigs: typeConfigs,
        initialWidth: 390,
      );

      expect(registry.offsetOfId('missing'), isNull);
    });

    test('unknown typeKey is a programming error', () {
      final items = [
        const ReaderItem<Object?>(id: 'x', typeKey: 'unknown', data: null),
      ];
      expect(
        () => ItemRegistry<Object?>.build(
          items: items,
          typeConfigs: typeConfigs,
          initialWidth: 390,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('duplicate ids are a programming error', () {
      final items = [
        const ReaderItem<Object?>(id: 'x', typeKey: 'verse', data: null),
        const ReaderItem<Object?>(id: 'x', typeKey: 'verse', data: null),
      ];
      expect(
        () => ItemRegistry<Object?>.build(
          items: items,
          typeConfigs: typeConfigs,
          initialWidth: 390,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('ItemRegistry — measurement', () {
    test('reportMeasuredHeight returns delta', () {
      final items = buildItems(20);
      final registry = ItemRegistry<Object?>.build(
        items: items,
        typeConfigs: typeConfigs,
        initialWidth: 390,
      );

      final offsetBefore = registry.offsetOfIndex(10);
      final delta = registry.reportMeasuredHeight(5, 100.0);
      final offsetAfter = registry.offsetOfIndex(10);

      expect(offsetAfter, offsetBefore + delta);
    });

    test('measurement updates entry metadata', () {
      final items = buildItems(5);
      final registry = ItemRegistry<Object?>.build(
        items: items,
        typeConfigs: typeConfigs,
        initialWidth: 390,
      );

      registry.reportMeasuredHeight(2, 73.5);

      final entry = registry.heightEntryAt(2);
      expect(entry.height, 73.5);
      expect(entry.tier, HeightTier.measured);
      expect(entry.confidence, 1.0);
      expect(entry.measuredAtWidth, 390);
    });
  });

  group('ItemRegistry — insert/remove', () {
    test('insert updates ID index', () {
      final items = buildItems(10);
      final registry = ItemRegistry<Object?>.build(
        items: items,
        typeConfigs: typeConfigs,
        initialWidth: 390,
      );

      registry.insert(
        5,
        const ReaderItem<Object?>(id: 'new_item', typeKey: 'text', data: null),
      );

      expect(registry.itemCount, 11);
      expect(registry.indexOfId('new_item'), 5);
      expect(registry.indexOfId('item_5'), 6);
      expect(registry.indexOfId('item_9'), 10);
    });

    test('insert with custom estimated height', () {
      final items = buildItems(5);
      final registry = ItemRegistry<Object?>.build(
        items: items,
        typeConfigs: typeConfigs,
        initialWidth: 390,
      );

      registry.insert(
        2,
        const ReaderItem<Object?>(id: 'custom', typeKey: 'text', data: null),
        estimatedHeight: 123.0,
      );

      expect(registry.heightEntryAt(2).height, 123.0);
    });

    test('remove updates ID index', () {
      final items = buildItems(10);
      final registry = ItemRegistry<Object?>.build(
        items: items,
        typeConfigs: typeConfigs,
        initialWidth: 390,
      );

      registry.removeAt(3);

      expect(registry.itemCount, 9);
      expect(registry.indexOfId('item_3'), isNull);
      expect(registry.indexOfId('item_4'), 3);
    });
  });

  group('ItemRegistry — width change', () {
    test('invariant items unchanged', () {
      final items = [
        const ReaderItem<Object?>(id: 'h1', typeKey: 'header', data: null),
        const ReaderItem<Object?>(id: 't1', typeKey: 'text', data: null),
      ];
      final registry = ItemRegistry<Object?>.build(
        items: items,
        typeConfigs: typeConfigs,
        initialWidth: 390,
      );

      final headerHeightBefore = registry.heightEntryAt(0).height;
      registry.onWidthChanged(500);
      final headerHeightAfter = registry.heightEntryAt(0).height;

      expect(headerHeightAfter, headerHeightBefore);
    });

    test('proportional items recomputed', () {
      final items = [
        const ReaderItem<Object?>(
          id: 'img1',
          typeKey: 'image',
          data: {'aspectRatio': 1.5},
        ),
      ];
      final registry = ItemRegistry<Object?>.build(
        items: items,
        typeConfigs: typeConfigs,
        initialWidth: 300,
      );

      expect(registry.heightEntryAt(0).height, 200.0); // 300/1.5

      registry.onWidthChanged(450);
      expect(registry.heightEntryAt(0).height, 300.0); // 450/1.5
    });

    test('updates currentWidth', () {
      final items = buildItems(5);
      final registry = ItemRegistry<Object?>.build(
        items: items,
        typeConfigs: typeConfigs,
        initialWidth: 390,
      );

      registry.onWidthChanged(500);
      expect(registry.currentWidth, 500);
    });
  });

  group('ItemRegistry — sensitivity', () {
    test('returns correct sensitivity per type', () {
      final items = [
        const ReaderItem<Object?>(id: 'h', typeKey: 'header', data: null),
        const ReaderItem<Object?>(id: 't', typeKey: 'text', data: null),
        const ReaderItem<Object?>(
          id: 'i',
          typeKey: 'image',
          data: {'aspectRatio': 1.5},
        ),
      ];
      final registry = ItemRegistry<Object?>.build(
        items: items,
        typeConfigs: typeConfigs,
        initialWidth: 390,
      );

      expect(registry.sensitivityAt(0), WidthSensitivity.invariant);
      expect(registry.sensitivityAt(1), WidthSensitivity.dependent);
      expect(registry.sensitivityAt(2), WidthSensitivity.proportional);
    });
  });
}
