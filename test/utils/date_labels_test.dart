import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:aura/utils/date_labels.dart';
import 'package:aura/utils/period_end_messages.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting();
  });

  group('dayMonthLabelWithYear', () {
    test('mismo ano: el formato de dayMonthLabel, sin ano', () {
      expect(dayMonthLabelWithYear('2026-10-04', today: '2026-10-10'),
          '4 de octubre');
      expect(dayMonthLabelWithYear('2026-01-31', today: '2026-12-31'),
          dayMonthLabel('2026-01-31'));
    });

    test('otro ano: con el ano', () {
      expect(dayMonthLabelWithYear('2025-12-28', today: '2026-01-05'),
          '28 de diciembre de 2025');
      expect(dayMonthLabelWithYear('2027-03-01', today: '2026-12-31'),
          '1 de marzo de 2027');
    });

    test('dias del cambio de horario de Chile', () {
      expect(dayMonthLabelWithYear('2026-09-06', today: '2026-10-10'),
          '6 de septiembre');
      expect(dayMonthLabelWithYear('2026-04-05', today: '2027-01-01'),
          '5 de abril de 2026');
    });
  });
}
