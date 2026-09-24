/// The engine's jump error estimate spans whole buckets through the
/// error tree, so it costs O(B + log(N/B)) rather than a walk over
/// every item in between.
library;

import 'dart:math';

import 'package:flutter_reader/flutter_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ChunkedHeightIndex indexOf(int count, Random random, {int bucket = 16}) =>
      ChunkedHeightIndex.build([
        for (var i = 0; i < count; i++)
          HeightEntry(
            height: 20 + random.nextInt(80).toDouble(),
            tier: HeightTier.values[random.nextInt(3)],
            confidence: random.nextDouble(),
          ),
      ], targetBucketSize: bucket);

  double bruteForce(ChunkedHeightIndex index, int from, int to) {
    final lo = min(from, to);
    final hi = max(from, to);
    var sum = 0.0;
    for (var i = lo; i < hi; i++) {
      final e = index.entryAt(i);
      if (e.tier != HeightTier.measured) sum += e.height * (1 - e.confidence);
    }
    return sum;
  }

  test('matches a brute-force sum over random ranges', () {
    final random = Random(7);
    final index = indexOf(1000, random);
    for (var trial = 0; trial < 300; trial++) {
      final a = random.nextInt(1000);
      final b = random.nextInt(1000);
      expect(
        index.estimatedJumpError(a, b),
        closeTo(bruteForce(index, a, b), 1e-6),
        reason: 'range $a..$b',
      );
    }
  });

  test('stays right through updates, inserts and removals', () {
    final random = Random(11);
    final index = indexOf(500, random);
    for (var step = 0; step < 200; step++) {
      switch (random.nextInt(3)) {
        case 0:
          index.updateHeight(
            random.nextInt(index.itemCount),
            newHeight: 10 + random.nextInt(90).toDouble(),
            tier: HeightTier.values[random.nextInt(3)],
            confidence: random.nextDouble(),
          );
        case 1:
          index.insert(
            random.nextInt(index.itemCount + 1),
            HeightEntry(height: 40, confidence: 0.3),
          );
        case _:
          if (index.itemCount > 1) {
            index.removeAt(random.nextInt(index.itemCount));
          }
      }
      final a = random.nextInt(index.itemCount);
      final b = random.nextInt(index.itemCount);
      expect(
        index.estimatedJumpError(a, b),
        closeTo(bruteForce(index, a, b), 1e-6),
        reason: 'step $step, range $a..$b',
      );
    }
  });

  test('a far jump costs about as much as a near one', () {
    final random = Random(3);
    final index = indexOf(200000, random, bucket: 128);
    final watch = Stopwatch()..start();
    for (var i = 0; i < 200; i++) {
      index.estimatedJumpError(0, 199999);
    }
    final far = watch.elapsedMicroseconds / 200;
    watch.reset();
    for (var i = 0; i < 200; i++) {
      index.estimatedJumpError(0, 10);
    }
    final near = watch.elapsedMicroseconds / 200;
    expect(far, lessThan(50), reason: 'far $far µs, near $near µs');
  }, tags: ['benchmark']);
}
