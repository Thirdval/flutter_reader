import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_reader/flutter_reader.dart';

void main() {
  group('ScrollCompensator', () {
    test('compensates changes above anchor', () {
      final comp = ScrollCompensator();
      comp.setAnchor(10);

      comp.reportHeightChange(5, 20.0);
      expect(comp.consumeCompensation(), 20.0);
    });

    test('ignores changes at anchor', () {
      final comp = ScrollCompensator();
      comp.setAnchor(10);

      comp.reportHeightChange(10, 20.0);
      expect(comp.consumeCompensation(), 0.0);
    });

    test('ignores changes below anchor', () {
      final comp = ScrollCompensator();
      comp.setAnchor(10);

      comp.reportHeightChange(15, -10.0);
      expect(comp.consumeCompensation(), 0.0);
    });

    test('accumulates multiple above-anchor changes', () {
      final comp = ScrollCompensator();
      comp.setAnchor(10);

      comp.reportHeightChange(3, 10.0);
      comp.reportHeightChange(7, -5.0);
      comp.reportHeightChange(12, 100.0); // below, ignored

      expect(comp.consumeCompensation(), 5.0);
    });

    test('consume resets pending', () {
      final comp = ScrollCompensator();
      comp.setAnchor(10);

      comp.reportHeightChange(5, 20.0);
      expect(comp.consumeCompensation(), 20.0);
      expect(comp.consumeCompensation(), 0.0);
    });

    test('zero delta ignored', () {
      final comp = ScrollCompensator();
      comp.setAnchor(10);

      comp.reportHeightChange(5, 0.0);
      expect(comp.hasPendingCompensation, isFalse);
    });

    test('batch changes', () {
      final comp = ScrollCompensator();
      comp.setAnchor(10);

      comp.reportHeightChanges({
        3: 10.0, // above → counted
        7: -5.0, // above → counted
        10: 50.0, // at → ignored
        15: 30.0, // below → ignored
      });

      expect(comp.consumeCompensation(), 5.0);
    });

    test('reset clears everything', () {
      final comp = ScrollCompensator();
      comp.setAnchor(10);
      comp.reportHeightChange(5, 20.0);

      comp.reset();

      expect(comp.anchorIndex, 0);
      expect(comp.consumeCompensation(), 0.0);
    });

    test('negative delta (item shrunk)', () {
      final comp = ScrollCompensator();
      comp.setAnchor(10);

      comp.reportHeightChange(5, -30.0);
      expect(comp.consumeCompensation(), -30.0);
    });
  });
}
