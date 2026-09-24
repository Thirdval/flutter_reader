import 'package:flutter/widgets.dart';
import 'package:flutter_reader/flutter_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const style = TextStyle(fontSize: 16);
  late TextPremeasurer premeasurer;

  setUp(() => premeasurer = TextPremeasurer());
  tearDown(() => premeasurer.dispose());

  test('a line of text is at least a line high', () {
    final estimate = premeasurer.measureText(
      text: 'Hello',
      style: style,
      maxWidth: 400,
    );
    expect(estimate.height, greaterThan(0));
    expect(estimate.confidence, 0.9);
  });

  test('padding is added', () {
    final bare = premeasurer.measureText(
      text: 'Hello',
      style: style,
      maxWidth: 400,
    );
    final padded = premeasurer.measureText(
      text: 'Hello',
      style: style,
      maxWidth: 400,
      padding: const EdgeInsets.symmetric(vertical: 8),
    );
    expect(padded.height, bare.height + 16);
  });

  test('a narrower width wraps into more lines', () {
    const text = 'The quick brown fox jumps over the lazy dog again and again';
    final wide = premeasurer.measureText(
      text: text,
      style: style,
      maxWidth: 800,
    );
    final narrow = premeasurer.measureText(
      text: text,
      style: style,
      maxWidth: 120,
    );
    expect(narrow.height, greaterThan(wide.height));
  });

  test('no room gives the padding only, at low confidence', () {
    final estimate = premeasurer.measureText(
      text: 'x',
      style: style,
      maxWidth: 10,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
    expect(estimate.height, 8);
    expect(estimate.confidence, 0.5);
  });

  test('rich spans measure at a lower confidence', () {
    final estimate = premeasurer.measureTextSpan(
      textSpan: const TextSpan(text: 'Hello', style: style),
      maxWidth: 400,
    );
    expect(estimate.confidence, 0.85);
  });

  test('estimators plug into a type config', () {
    final config = ItemTypeConfig<String>(
      typeName: 'p',
      defaultHeight: 20,
      estimator: premeasurer.createEstimator<String>(
        textExtractor: (data) => data,
        style: style,
      ),
    );
    expect(config.estimator!('Hello', 400).height, greaterThan(0));
    final rich = premeasurer.createRichEstimator<String>(
      spanBuilder: (data) => TextSpan(text: data, style: style),
    );
    expect(rich('Hello', 400).confidence, 0.85);
  });

  test('an RTL premeasurer measures the same height', () {
    final rtl = TextPremeasurer(textDirection: TextDirection.rtl);
    addTearDown(rtl.dispose);
    expect(
      rtl.measureText(text: 'שלום עולם', style: style, maxWidth: 300).height,
      premeasurer
          .measureText(text: 'שלום עולם', style: style, maxWidth: 300)
          .height,
    );
  });
}
