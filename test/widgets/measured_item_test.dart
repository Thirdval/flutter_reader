import 'package:flutter/widgets.dart';
import 'package:flutter_reader/flutter_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(double height, int index, ValueChanged<double> onMeasured) =>
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: MeasuredItem(
            itemIndex: index,
            onMeasured: onMeasured,
            child: SizedBox(height: height, width: 100),
          ),
        ),
      );

  testWidgets('reports the height after layout, and again when it changes', (
    tester,
  ) async {
    final heights = <double>[];
    await tester.pumpWidget(host(75, 0, heights.add));
    await tester.pump();
    expect(heights, [75.0]);
    await tester.pumpWidget(host(75, 0, heights.add));
    await tester.pump();
    expect(heights, [75.0], reason: 'unchanged height is not re-reported');
    await tester.pumpWidget(host(80, 0, heights.add));
    await tester.pump();
    expect(heights, [75.0, 80.0]);
  });

  testWidgets('a new item in the same slot reports even at the same height', (
    tester,
  ) async {
    final heights = <double>[];
    await tester.pumpWidget(host(75, 0, heights.add));
    await tester.pump();
    await tester.pumpWidget(host(75, 1, heights.add));
    await tester.pump();
    expect(heights, [75.0, 75.0]);
  });
}
