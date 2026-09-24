import 'package:flutter/widgets.dart';
import 'package:flutter_reader/flutter_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const style = TextStyle(fontSize: 16);

  ReaderEngine<String> engineOf(int count) => ReaderEngine<String>(
    registry: ItemRegistry<String>.build(
      items: [
        for (var i = 0; i < count; i++)
          ReaderItem<String>(
            id: 'p$i',
            typeKey: 'p',
            data: 'Paragraph $i ' * (i + 1),
          ),
      ],
      typeConfigs: const {
        'p': ItemTypeConfig<String>(
          typeName: 'p',
          defaultHeight: 40,
          defaultConfidence: 0.2,
        ),
      },
      initialWidth: 300,
    ),
  );

  MeasurementScheduler<String> schedulerOf(
    ReaderEngine<String> engine, {
    int batchSize = 10,
    VoidCallback? onComplete,
  }) => MeasurementScheduler<String>(
    engine: engine,
    premeasurer: TextPremeasurer(),
    configs: const {
      'p': PremeasureConfig<String>(textExtractor: _identity, style: style),
    },
    batchSize: batchSize,
    onComplete: onComplete,
  );

  test('a batch measures the least confident items as premeasured', () {
    final engine = engineOf(25);
    final scheduler = schedulerOf(engine);
    addTearDown(scheduler.dispose);
    expect(scheduler.measureBatch(), 10);
    var premeasured = 0;
    for (var i = 0; i < 25; i++) {
      final entry = engine.registry.heightEntryAt(i);
      if (entry.tier == HeightTier.premeasured) {
        premeasured++;
        expect(entry.confidence, 0.9);
      }
    }
    expect(premeasured, 10);
  });

  test('a measured item is never downgraded', () {
    final engine = engineOf(3);
    engine.reportMeasuredHeight(0, 123);
    final scheduler = schedulerOf(engine);
    addTearDown(scheduler.dispose);
    while (scheduler.measureBatch() > 0) {}
    expect(engine.registry.heightEntryAt(0).height, 123);
    expect(engine.registry.heightEntryAt(0).tier, HeightTier.measured);
  });

  test('types without a config are skipped', () {
    final engine = engineOf(5);
    final scheduler = MeasurementScheduler<String>(
      engine: engine,
      premeasurer: TextPremeasurer(),
      configs: const {},
    );
    addTearDown(scheduler.dispose);
    expect(scheduler.measureBatch(), 0);
  });

  testWidgets('start runs batches after frames until done', (tester) async {
    final engine = engineOf(25);
    var completed = 0;
    final scheduler = schedulerOf(
      engine,
      batchSize: 10,
      onComplete: () => completed++,
    );
    addTearDown(scheduler.dispose);
    await tester.pumpWidget(const SizedBox());
    scheduler.start();
    expect(scheduler.isRunning, isTrue);
    scheduler.start(); // idempotent
    for (var i = 0; i < 5; i++) {
      await tester.pump();
    }
    expect(scheduler.isRunning, isFalse);
    expect(completed, 1);
    expect(engine.averageConfidence, closeTo(0.9, 0.001));
  });

  testWidgets('stop halts before the next batch', (tester) async {
    final engine = engineOf(25);
    final scheduler = schedulerOf(engine, batchSize: 5);
    addTearDown(scheduler.dispose);
    await tester.pumpWidget(const SizedBox());
    scheduler.start();
    await tester.pump();
    scheduler.stop();
    await tester.pump();
    await tester.pump();
    expect(engine.nextItemsToMeasure(count: 25).length, greaterThan(10));
  });
}

String _identity(String data) => data;
