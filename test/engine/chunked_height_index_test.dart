import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reader/flutter_reader.dart';

void main() {
  ChunkedHeightIndex buildIndex(
    int count, {
    double height = 50.0,
    int bucketSize = 4,
  }) {
    final entries = List.generate(
      count,
      (i) => HeightEntry(height: height, confidence: 0.5),
    );
    return ChunkedHeightIndex.build(entries, targetBucketSize: bucketSize);
  }

  group('ChunkedHeightIndex — construction', () {
    test('basic construction', () {
      final index = buildIndex(10);
      expect(index.itemCount, 10);
      expect(index.totalHeight, 500.0);
    });

    test('empty construction', () {
      final index = ChunkedHeightIndex.build([], targetBucketSize: 4);
      expect(index.itemCount, 0);
      expect(index.totalHeight, 0.0);
    });

    test('single item', () {
      final index = ChunkedHeightIndex.build([
        HeightEntry(height: 42.0),
      ], targetBucketSize: 4);
      expect(index.itemCount, 1);
      expect(index.totalHeight, 42.0);
      expect(index.offsetOfItem(0), 0.0);
    });

    test('bucket count is correct', () {
      final index = buildIndex(10, bucketSize: 4);
      expect(index.bucketCount, 3); // ceil(10/4) = 3
    });
  });

  group('ChunkedHeightIndex — offsetOfItem', () {
    test('uniform heights', () {
      final index = buildIndex(10, height: 50.0, bucketSize: 4);
      expect(index.offsetOfItem(0), 0.0);
      expect(index.offsetOfItem(1), 50.0);
      expect(index.offsetOfItem(5), 250.0);
      expect(index.offsetOfItem(9), 450.0);
    });

    test('variable heights', () {
      final entries = [
        10,
        20,
        30,
        40,
        50,
        60,
      ].map((h) => HeightEntry(height: h.toDouble())).toList();
      final index = ChunkedHeightIndex.build(entries, targetBucketSize: 3);

      expect(index.offsetOfItem(0), 0);
      expect(index.offsetOfItem(1), 10);
      expect(index.offsetOfItem(2), 30);
      expect(index.offsetOfItem(3), 60); // crosses bucket boundary
      expect(index.offsetOfItem(4), 100);
      expect(index.offsetOfItem(5), 150);
    });
  });

  group('ChunkedHeightIndex — itemAtOffset', () {
    test('variable heights', () {
      final entries = [
        10,
        20,
        30,
        40,
        50,
        60,
      ].map((h) => HeightEntry(height: h.toDouble())).toList();
      final index = ChunkedHeightIndex.build(entries, targetBucketSize: 3);

      expect(index.itemAtOffset(0), 0);
      expect(index.itemAtOffset(5), 0);
      expect(index.itemAtOffset(10), 1);
      expect(index.itemAtOffset(29), 1);
      expect(index.itemAtOffset(30), 2);
      expect(index.itemAtOffset(60), 3); // crosses bucket
      expect(index.itemAtOffset(150), 5);
      expect(index.itemAtOffset(209), 5);
    });

    test('edge cases', () {
      final index = buildIndex(5, height: 50.0, bucketSize: 3);
      expect(index.itemAtOffset(-1), 0);
      expect(index.itemAtOffset(250), -1); // beyond end
    });

    test('empty index', () {
      final index = ChunkedHeightIndex.build([], targetBucketSize: 4);
      expect(index.itemAtOffset(0), -1);
    });
  });

  group('ChunkedHeightIndex — updateHeight', () {
    test('returns correct delta', () {
      final index = buildIndex(10, height: 50.0, bucketSize: 4);

      final delta = index.updateHeight(
        3,
        newHeight: 75.0,
        tier: HeightTier.measured,
        confidence: 1.0,
      );

      expect(delta, 25.0);
      expect(index.totalHeight, 525.0);
      expect(index.offsetOfItem(4), 225.0); // 50*3 + 75
    });

    test('zero delta when height unchanged', () {
      final index = buildIndex(5, height: 50.0, bucketSize: 3);
      final delta = index.updateHeight(
        2,
        newHeight: 50.0,
        tier: HeightTier.measured,
        confidence: 1.0,
      );
      expect(delta, 0.0);
    });

    test('updates entry metadata', () {
      final index = buildIndex(5, height: 50.0, bucketSize: 3);
      index.updateHeight(
        2,
        newHeight: 70.0,
        tier: HeightTier.measured,
        confidence: 1.0,
        measuredAtWidth: 390.0,
      );

      final entry = index.entryAt(2);
      expect(entry.height, 70.0);
      expect(entry.tier, HeightTier.measured);
      expect(entry.confidence, 1.0);
      expect(entry.measuredAtWidth, 390.0);
    });
  });

  group('ChunkedHeightIndex — insert', () {
    test('basic insert', () {
      final index = buildIndex(10, height: 50.0, bucketSize: 4);

      index.insert(5, HeightEntry(height: 100.0));

      expect(index.itemCount, 11);
      expect(index.totalHeight, 600.0);
      expect(index.offsetOfItem(5), 250.0);
      expect(index.offsetOfItem(6), 350.0);
    });

    test('insert at beginning', () {
      final index = buildIndex(5, height: 50.0, bucketSize: 3);
      index.insert(0, HeightEntry(height: 100.0));

      expect(index.itemCount, 6);
      expect(index.offsetOfItem(0), 0.0);
      expect(index.offsetOfItem(1), 100.0);
    });

    test('insert at end', () {
      final index = buildIndex(5, height: 50.0, bucketSize: 3);
      index.insert(5, HeightEntry(height: 100.0));

      expect(index.itemCount, 6);
      expect(index.offsetOfItem(5), 250.0);
    });

    test('insert triggers bucket split', () {
      final index = buildIndex(8, height: 50.0, bucketSize: 4);
      final initialBuckets = index.bucketCount;

      for (var i = 0; i < 7; i++) {
        index.insert(0, HeightEntry(height: 25.0));
      }

      expect(index.itemCount, 15);
      expect(index.bucketCount, greaterThan(initialBuckets));
      expect(index.totalHeight, 8 * 50.0 + 7 * 25.0);
    });

    test('insert into empty', () {
      final index = ChunkedHeightIndex.build([], targetBucketSize: 4);
      index.insert(0, HeightEntry(height: 42.0));
      expect(index.itemCount, 1);
      expect(index.totalHeight, 42.0);
    });
  });

  group('ChunkedHeightIndex — remove', () {
    test('basic remove', () {
      final entries = [
        10,
        20,
        30,
        40,
        50,
      ].map((h) => HeightEntry(height: h.toDouble())).toList();
      final index = ChunkedHeightIndex.build(entries, targetBucketSize: 3);

      index.removeAt(2); // remove 30

      expect(index.itemCount, 4);
      expect(index.totalHeight, 120.0);
      expect(index.offsetOfItem(2), 30.0); // was "40", now at 10+20
    });

    test('remove first item', () {
      final index = buildIndex(5, height: 50.0, bucketSize: 3);
      index.removeAt(0);
      expect(index.itemCount, 4);
      expect(index.offsetOfItem(0), 0.0);
    });

    test('remove last item', () {
      final index = buildIndex(5, height: 50.0, bucketSize: 3);
      index.removeAt(4);
      expect(index.itemCount, 4);
      expect(index.totalHeight, 200.0);
    });
  });

  group('ChunkedHeightIndex — bulk operations', () {
    test('insertAll small batch', () {
      final index = buildIndex(10, height: 50.0, bucketSize: 4);
      final newEntries = List.generate(3, (_) => HeightEntry(height: 25.0));
      index.insertAll(5, newEntries);
      expect(index.itemCount, 13);
      expect(index.totalHeight, 10 * 50.0 + 3 * 25.0);
    });

    test('insertAll large batch triggers rebuild', () {
      final index = buildIndex(10, height: 50.0, bucketSize: 4);
      final newEntries = List.generate(
        10, // larger than bucketSize
        (_) => HeightEntry(height: 30.0),
      );
      index.insertAll(5, newEntries);
      expect(index.itemCount, 20);
    });

    test('removeRange', () {
      final index = buildIndex(10, height: 50.0, bucketSize: 4);
      index.removeRange(3, 4); // remove items 3,4,5,6
      expect(index.itemCount, 6);
      expect(index.totalHeight, 300.0);
    });
  });

  group('ChunkedHeightIndex — visibleRange', () {
    test('basic visible range', () {
      final index = buildIndex(100, height: 50.0, bucketSize: 16);
      final range = index.visibleRange(500, 300);
      expect(range.$1, 10); // 500/50
      expect(range.$2, 16); // (500+300)/50
    });

    test('visible range at start', () {
      final index = buildIndex(100, height: 50.0, bucketSize: 16);
      final range = index.visibleRange(0, 300);
      expect(range.$1, 0);
      expect(range.$2, 6);
    });

    test('visible range at end', () {
      final index = buildIndex(100, height: 50.0, bucketSize: 16);
      final range = index.visibleRange(4800, 300);
      expect(range.$1, 96);
      expect(range.$2, 99);
    });
  });

  group('ChunkedHeightIndex — diagnostics', () {
    test('lowConfidenceItems', () {
      final entries = List.generate(
        10,
        (i) => HeightEntry(height: 50.0, confidence: i < 3 ? 0.2 : 0.9),
      );
      final index = ChunkedHeightIndex.build(entries, targetBucketSize: 5);

      final lowConf = index.lowConfidenceItems(threshold: 0.5);
      expect(lowConf.length, 3);
      expect(lowConf, containsAll([0, 1, 2]));
    });

    test('averageConfidence', () {
      final entries = List.generate(
        4,
        (i) => HeightEntry(height: 50.0, confidence: 0.25 * (i + 1)),
      );
      final index = ChunkedHeightIndex.build(entries, targetBucketSize: 4);
      expect(index.averageConfidence, closeTo(0.625, 0.01));
    });

    test('estimatedJumpError', () {
      final entries = [
        HeightEntry(height: 50.0, tier: HeightTier.measured, confidence: 1.0),
        HeightEntry(height: 50.0, tier: HeightTier.estimate, confidence: 0.5),
        HeightEntry(height: 50.0, tier: HeightTier.estimate, confidence: 0.5),
        HeightEntry(height: 50.0, tier: HeightTier.measured, confidence: 1.0),
      ];
      final index = ChunkedHeightIndex.build(entries, targetBucketSize: 4);

      final error = index.estimatedJumpError(0, 4);
      // Items 1,2 are estimates: 50*(1-0.5) + 50*(1-0.5) = 50
      expect(error, closeTo(50.0, 0.01));
    });
  });

  group('ChunkedHeightIndex — round trip integrity', () {
    test('offset → itemAt round trip for 1000 items', () {
      final entries = List.generate(
        1000,
        (i) => HeightEntry(height: 40.0 + (i % 7) * 10.0),
      );
      final index = ChunkedHeightIndex.build(entries, targetBucketSize: 64);

      for (var i = 0; i < 1000; i++) {
        final offset = index.offsetOfItem(i);
        final recovered = index.itemAtOffset(offset);
        expect(recovered, i, reason: 'Round trip failed for item $i');
      }
    });

    test('insert + delete preserves total', () {
      final index = buildIndex(100, height: 50.0, bucketSize: 16);
      final originalTotal = index.totalHeight;

      index.insert(50, HeightEntry(height: 77.0));
      index.removeAt(50);

      expect(index.totalHeight, closeTo(originalTotal, 0.01));
      expect(index.itemCount, 100);
    });
  });
}
