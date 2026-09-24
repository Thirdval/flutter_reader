import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reader/flutter_reader.dart';

void main() {
  final typeConfigs = {
    'verse': const ItemTypeConfig<Object?>(
      typeName: 'verse',
      defaultHeight: 56.0,
      defaultConfidence: 0.3,
      widthSensitivity: WidthSensitivity.dependent,
    ),
    'chapter': const ItemTypeConfig<Object?>(
      typeName: 'chapter',
      defaultHeight: 44.0,
      defaultConfidence: 0.95,
      widthSensitivity: WidthSensitivity.invariant,
    ),
  };

  ReaderEngine<Object?> buildBibleEngine({int verseCount = 1000}) {
    final items = <ReaderItem<Object?>>[];
    var verseNum = 0;
    for (var ch = 1; ch <= (verseCount / 25).ceil(); ch++) {
      items.add(
        ReaderItem<Object?>(id: 'ch_$ch', typeKey: 'chapter', data: null),
      );
      for (var v = 1; v <= 25 && verseNum < verseCount; v++, verseNum++) {
        items.add(
          ReaderItem<Object?>(id: 'v_${ch}_$v', typeKey: 'verse', data: null),
        );
      }
    }

    final registry = ItemRegistry<Object?>.build(
      items: items,
      typeConfigs: typeConfigs,
      initialWidth: 390,
    );

    final engine = ReaderEngine<Object?>(registry: registry);
    engine.setViewportHeight(800);
    return engine;
  }

  group('ReaderEngine — jump', () {
    test('jump to item by ID', () {
      final engine = buildBibleEngine(verseCount: 500);

      final result = engine.jumpToId('v_10_5');
      expect(result, isNotNull);
      expect(result!.pixelOffset, greaterThan(0));
    });

    test('jump to item by index', () {
      final engine = buildBibleEngine(verseCount: 100);

      final result = engine.jumpToIndex(50);
      expect(result.pixelOffset, greaterThan(0));
    });

    test('jump to nonexistent ID returns null', () {
      final engine = buildBibleEngine(verseCount: 100);
      expect(engine.jumpToId('nonexistent'), isNull);
    });

    test('jump reports estimated error', () {
      final engine = buildBibleEngine(verseCount: 500);
      engine.reportScrollOffset(0);

      final result = engine.jumpToIndex(400);
      // Most items are estimates, so error should be > 0
      expect(result.estimatedError, greaterThan(0));
    });
  });

  group('ReaderEngine — measurement + compensation', () {
    test('measurement above viewport produces compensation', () {
      final engine = buildBibleEngine(verseCount: 100);

      // Scroll to middle
      final jump = engine.jumpToIndex(50);
      engine.reportScrollOffset(jump.pixelOffset);

      // Measure item above viewport
      final result = engine.reportMeasuredHeight(20, 100.0);
      expect(result.scrollCompensation, isNot(0.0));
    });

    test('measurement below viewport produces zero compensation', () {
      final engine = buildBibleEngine(verseCount: 100);

      // Stay at top
      engine.reportScrollOffset(0);

      // Measure item below viewport
      final result = engine.reportMeasuredHeight(80, 100.0);
      expect(result.scrollCompensation, 0.0);
    });

    test('batch measurement returns total compensation', () {
      final engine = buildBibleEngine(verseCount: 100);

      final jump = engine.jumpToIndex(50);
      engine.reportScrollOffset(jump.pixelOffset);

      final compensation = engine.reportMeasuredHeights({
        10: 100.0, // above anchor
        20: 80.0, // above anchor
        60: 200.0, // below anchor
      });

      // Only items 10 and 20 contribute to compensation
      expect(compensation, isNot(0.0));
    });
  });

  group('ReaderEngine — dynamic content', () {
    test('insert above viewport produces compensation', () {
      final engine = buildBibleEngine(verseCount: 100);

      final jump = engine.jumpToIndex(50);
      engine.reportScrollOffset(jump.pixelOffset);

      final compensation = engine.insertItem(
        10,
        const ReaderItem<Object?>(id: 'new', typeKey: 'verse', data: null),
      );

      expect(compensation, greaterThan(0));
      expect(engine.itemCount, greaterThan(100));
    });

    test('insert below viewport produces zero compensation', () {
      final engine = buildBibleEngine(verseCount: 100);

      engine.reportScrollOffset(0);

      final compensation = engine.insertItem(
        90,
        const ReaderItem<Object?>(id: 'new', typeKey: 'verse', data: null),
      );

      expect(compensation, 0.0);
    });

    test('remove above viewport produces negative compensation', () {
      final engine = buildBibleEngine(verseCount: 100);

      final jump = engine.jumpToIndex(50);
      engine.reportScrollOffset(jump.pixelOffset);

      final compensation = engine.removeItem(10);
      expect(compensation, lessThan(0));
    });
  });

  group('ReaderEngine — visibility', () {
    test('visibility at scroll offset 0', () {
      final engine = buildBibleEngine(verseCount: 100);

      engine.reportScrollOffset(0);
      final vis = engine.visibility;

      expect(vis.firstVisible, 0);
      expect(vis.lastVisible, greaterThan(0));
      expect(vis.anchorIndex, 0);
      expect(vis.scrollOffset, 0.0);
    });

    test('visibility updates on scroll', () {
      final engine = buildBibleEngine(verseCount: 100);

      engine.reportScrollOffset(500);
      final vis = engine.visibility;

      expect(vis.firstVisible, greaterThan(0));
      expect(vis.scrollOffset, 500.0);
    });

    test('visibility callback fires', () {
      final engine = buildBibleEngine(verseCount: 100);

      VisibilityState? lastState;
      engine.onVisibilityChanged = (state) {
        lastState = state;
      };

      engine.reportScrollOffset(500);
      expect(lastState, isNotNull);
      expect(lastState!.firstVisible, greaterThan(0));
    });
  });

  group('ReaderEngine — diagnostics', () {
    test('itemCount matches input', () {
      final engine = buildBibleEngine(verseCount: 100);
      // 100 verses + ceil(100/25) chapter headers
      expect(engine.itemCount, greaterThan(100));
    });

    test('totalHeight is positive', () {
      final engine = buildBibleEngine(verseCount: 100);
      expect(engine.totalHeight, greaterThan(0));
    });

    test('nextItemsToMeasure returns low-confidence items', () {
      final engine = buildBibleEngine(verseCount: 100);
      final toMeasure = engine.nextItemsToMeasure(count: 10);
      expect(toMeasure.length, lessThanOrEqualTo(10));
    });
  });

  group('ReaderEngine — full round trip', () {
    test('build → jump → measure → jump again', () {
      final engine = buildBibleEngine(verseCount: 500);

      // Jump to chapter 10
      final jump1 = engine.jumpToId('ch_10');
      expect(jump1, isNotNull);
      engine.reportScrollOffset(jump1!.pixelOffset);

      // Measure visible items with varying heights
      final vis = engine.visibility;
      for (var i = vis.firstVisible; i <= vis.lastVisible; i++) {
        engine.reportMeasuredHeight(i, 60.0 + (i % 3) * 10);
      }

      // Jump to chapter 15 — should be more accurate now
      final jump2 = engine.jumpToId('ch_15');
      expect(jump2, isNotNull);
      expect(jump2!.pixelOffset, greaterThan(jump1.pixelOffset));
    });

    test('accuracy improves with measurements', () {
      final engine = buildBibleEngine(verseCount: 200);

      // Initial confidence is low
      final initialConfidence = engine.averageConfidence;

      // Measure all items
      for (var i = 0; i < engine.itemCount; i++) {
        engine.reportMeasuredHeight(i, 55.0);
      }

      // Confidence should be 1.0 now
      expect(engine.averageConfidence, greaterThan(initialConfidence));
      expect(engine.averageConfidence, closeTo(1.0, 0.01));
    });
  });

  group('ReaderEngine — batch mutations', () {
    test('insertItems at end produces zero compensation when at top', () {
      final engine = buildBibleEngine(verseCount: 100);
      engine.reportScrollOffset(0);

      final oldCount = engine.itemCount;
      final items = List.generate(
        5,
        (i) => ReaderItem<Object?>(id: 'new_$i', typeKey: 'verse', data: null),
      );

      final compensation = engine.insertItems(engine.itemCount, items);
      expect(compensation, 0.0);
      expect(engine.itemCount, oldCount + 5);
    });

    test(
      'insertItems at 0 (prepend) produces positive compensation when scrolled',
      () {
        final engine = buildBibleEngine(verseCount: 100);
        final jump = engine.jumpToIndex(50);
        engine.reportScrollOffset(jump.pixelOffset);

        final items = List.generate(
          10,
          (i) => ReaderItem<Object?>(
            id: 'prepend_$i',
            typeKey: 'verse',
            data: null,
          ),
        );

        final compensation = engine.insertItems(0, items);
        expect(compensation, greaterThan(0));
      },
    );

    test('insertItems above anchor compensates, below does not', () {
      final engine = buildBibleEngine(verseCount: 100);
      final jump = engine.jumpToIndex(50);
      engine.reportScrollOffset(jump.pixelOffset);

      // Insert above
      final aboveItems = [
        const ReaderItem<Object?>(id: 'above', typeKey: 'verse', data: null),
      ];
      final compAbove = engine.insertItems(0, aboveItems);
      expect(compAbove, greaterThan(0));

      // Insert below (well past anchor)
      final belowItems = [
        const ReaderItem<Object?>(id: 'below', typeKey: 'verse', data: null),
      ];
      final compBelow = engine.insertItems(engine.itemCount, belowItems);
      expect(compBelow, 0.0);
    });

    test('removeItems above anchor produces negative compensation', () {
      final engine = buildBibleEngine(verseCount: 100);
      final jump = engine.jumpToIndex(50);
      engine.reportScrollOffset(jump.pixelOffset);

      final oldCount = engine.itemCount;
      final compensation = engine.removeItems(0, 5);
      expect(compensation, lessThan(0));
      expect(engine.itemCount, oldCount - 5);
    });

    test('removeItems below anchor produces zero compensation', () {
      final engine = buildBibleEngine(verseCount: 100);
      engine.reportScrollOffset(0);

      final oldCount = engine.itemCount;
      final compensation = engine.removeItems(oldCount - 5, 5);
      expect(compensation, 0.0);
      expect(engine.itemCount, oldCount - 5);
    });

    test('insertItems with empty list is no-op', () {
      final engine = buildBibleEngine(verseCount: 100);
      final oldCount = engine.itemCount;
      final compensation = engine.insertItems(0, []);
      expect(compensation, 0.0);
      expect(engine.itemCount, oldCount);
    });

    test('removeItems with count 0 is no-op', () {
      final engine = buildBibleEngine(verseCount: 100);
      final oldCount = engine.itemCount;
      final compensation = engine.removeItems(0, 0);
      expect(compensation, 0.0);
      expect(engine.itemCount, oldCount);
    });

    test('insertItems total height matches sum of individual heights', () {
      final engine = buildBibleEngine(verseCount: 100);
      final oldHeight = engine.totalHeight;

      final items = List.generate(
        20,
        (i) =>
            ReaderItem<Object?>(id: 'batch_$i', typeKey: 'verse', data: null),
      );

      engine.insertItems(engine.itemCount, items);
      // New total = old + 20 verse default heights (56.0 each)
      expect(engine.totalHeight, greaterThan(oldHeight));
      expect(engine.totalHeight, closeTo(oldHeight + 20 * 56.0, 0.1));
    });
  });
}
