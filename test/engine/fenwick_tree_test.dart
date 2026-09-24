import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reader/flutter_reader.dart';

void main() {
  group('FenwickTree', () {
    test('basic prefix sums', () {
      final tree = FenwickTree.fromList([10, 20, 30, 40]);
      expect(tree.prefixSum(0), 10);
      expect(tree.prefixSum(1), 30);
      expect(tree.prefixSum(2), 60);
      expect(tree.prefixSum(3), 100);
      expect(tree.totalSum, 100);
    });

    test('point update', () {
      final tree = FenwickTree.fromList([10, 20, 30, 40]);
      tree.update(1, 5); // 20 → 25
      expect(tree.prefixSum(0), 10);
      expect(tree.prefixSum(1), 35);
      expect(tree.prefixSum(2), 65);
      expect(tree.totalSum, 105);
    });

    test('set via old/new value', () {
      final tree = FenwickTree.fromList([10, 20, 30, 40]);
      tree.set(2, 30, 50); // 30 → 50
      expect(tree.prefixSum(2), 80); // 10+20+50
      expect(tree.totalSum, 120);
    });

    test('range sum', () {
      final tree = FenwickTree.fromList([10, 20, 30, 40]);
      expect(tree.rangeSum(1, 2), 50); // 20 + 30
      expect(tree.rangeSum(0, 3), 100);
      expect(tree.rangeSum(2, 2), 30);
    });

    test('findItemAtOffset — basic', () {
      // Heights [10, 20, 30, 40] → offsets 0, 10, 30, 60 → ends at 100
      final tree = FenwickTree.fromList([10, 20, 30, 40]);

      expect(tree.findItemAtOffset(0), 0);
      expect(tree.findItemAtOffset(5), 0);
      expect(tree.findItemAtOffset(9.99), 0);
      expect(tree.findItemAtOffset(10), 1);
      expect(tree.findItemAtOffset(25), 1);
      expect(tree.findItemAtOffset(30), 2);
      expect(tree.findItemAtOffset(59.99), 2);
      expect(tree.findItemAtOffset(60), 3);
      expect(tree.findItemAtOffset(99.99), 3);
    });

    test('findItemAtOffset — edge cases', () {
      final tree = FenwickTree.fromList([10, 20, 30, 40]);
      expect(tree.findItemAtOffset(100), -1); // beyond end
      expect(tree.findItemAtOffset(-1), 0); // negative
      expect(tree.findItemAtOffset(200), -1); // way beyond
    });

    test('findItemAtOffset — empty tree', () {
      final tree = FenwickTree(0);
      expect(tree.findItemAtOffset(0), -1);
    });

    test('fromList matches individual updates', () {
      final values = [15.0, 23.0, 7.0, 42.0, 31.0, 8.0, 19.0, 55.0];

      final tree1 = FenwickTree.fromList(values);
      final tree2 = FenwickTree(values.length);
      for (var i = 0; i < values.length; i++) {
        tree2.update(i, values[i]);
      }

      for (var i = 0; i < values.length; i++) {
        expect(
          tree1.prefixSum(i),
          tree2.prefixSum(i),
          reason: 'Mismatch at index $i',
        );
      }
    });

    test('large tree correctness (10K items)', () {
      final rng = Random(42);
      final values = List.generate(10000, (_) => rng.nextDouble() * 100);
      final tree = FenwickTree.fromList(values);

      var naiveSum = 0.0;
      for (var i = 0; i < 200; i++) {
        naiveSum += values[i];
        expect(
          (tree.prefixSum(i) - naiveSum).abs() < 1e-6,
          isTrue,
          reason: 'Mismatch at index $i',
        );
      }
    });

    test('resize grows', () {
      final tree = FenwickTree.fromList([10, 20, 30]);
      tree.resize(5);
      expect(tree.size, 5);
      expect(tree.prefixSum(2), 60);
      expect(tree.prefixSum(4), 60); // new positions are 0
    });

    test('resize shrinks', () {
      final tree = FenwickTree.fromList([10, 20, 30, 40, 50]);
      tree.resize(3);
      expect(tree.size, 3);
      expect(tree.totalSum, 60);
    });
  });
}
