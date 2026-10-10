import 'package:flutter_test/flutter_test.dart';

import 'package:aura/domain/backup_reminder.dart';

/// Datos inventados. Por defecto: activado, con registros, primer uso
/// hace mucho y sin respaldo.
bool recordar({
  String today = '2026-10-10',
  bool activado = true,
  bool hayRegistros = true,
  String primerUso = '2026-01-01',
  String? ultimoRespaldo,
  String? pospuestoHasta,
}) =>
    deberiaRecordarRespaldo(
      today: today,
      activado: activado,
      hayRegistros: hayRegistros,
      primerUso: primerUso,
      ultimoRespaldo: ultimoRespaldo,
      pospuestoHasta: pospuestoHasta,
    );

void main() {
  test('los plazos son 30, 7 y 7 dias', () {
    expect(diasUmbralRecordatorioRespaldo, 30);
    expect(diasGraciaRecordatorioRespaldo, 7);
    expect(diasPosponerRecordatorioRespaldo, 7);
  });

  group('sin respaldo previo', () {
    test('con registros y pasada la gracia: recuerda', () {
      expect(recordar(), isTrue);
    });

    test('sin registros: no recuerda', () {
      expect(recordar(hayRegistros: false), isFalse);
    });

    test('apagado: no recuerda', () {
      expect(recordar(activado: false), isFalse);
    });

    test('gracia: 0 y 6 dias desde el primer uso no, 7 si', () {
      expect(recordar(primerUso: '2026-10-10'), isFalse);
      expect(recordar(primerUso: '2026-10-04'), isFalse);
      expect(recordar(primerUso: '2026-10-03'), isTrue);
    });

    test('primer uso en el futuro (reloj atrasado): no recuerda', () {
      expect(recordar(primerUso: '2026-11-01'), isFalse);
    });
  });

  group('con respaldo previo', () {
    test('29 dias: no; 30 y 31: si', () {
      expect(recordar(ultimoRespaldo: '2026-09-11'), isFalse);
      expect(recordar(ultimoRespaldo: '2026-09-10'), isTrue);
      expect(recordar(ultimoRespaldo: '2026-09-09'), isTrue);
    });

    test('respaldo de hoy: no recuerda', () {
      expect(recordar(ultimoRespaldo: '2026-10-10'), isFalse);
    });

    test('respaldo con fecha futura (reloj atrasado): cuenta como reciente',
        () {
      expect(recordar(ultimoRespaldo: '2026-12-01'), isFalse);
      expect(recordar(ultimoRespaldo: '2027-10-10'), isFalse);
    });

    test('apagado o sin registros: no recuerda aunque este vencido', () {
      expect(
          recordar(ultimoRespaldo: '2026-01-01', activado: false), isFalse);
      expect(recordar(ultimoRespaldo: '2026-01-01', hayRegistros: false),
          isFalse);
    });

    test('la gracia tambien rige con un respaldo vencido', () {
      expect(recordar(primerUso: '2026-10-05', ultimoRespaldo: '2026-08-01'),
          isFalse);
    });

    test('cambio de mes y de anio', () {
      // 30 dias que cruzan febrero.
      expect(recordar(today: '2026-03-02', ultimoRespaldo: '2026-01-31'),
          isTrue);
      expect(recordar(today: '2026-03-01', ultimoRespaldo: '2026-01-31'),
          isFalse);
      expect(recordar(today: '2027-01-09', ultimoRespaldo: '2026-12-10'),
          isTrue);
      expect(recordar(today: '2027-01-08', ultimoRespaldo: '2026-12-10'),
          isFalse);
    });
  });

  group('pospuesto ("Ahora no")', () {
    test('antes del dia de pospuestoHasta: no recuerda', () {
      expect(recordar(pospuestoHasta: '2026-10-11'), isFalse);
      expect(recordar(pospuestoHasta: '2026-10-17'), isFalse);
    });

    test('el dia exacto de pospuestoHasta: vuelve a recordar', () {
      expect(recordar(pospuestoHasta: '2026-10-10'), isTrue);
    });

    test('despues de pospuestoHasta: recuerda', () {
      expect(recordar(pospuestoHasta: '2026-10-03'), isTrue);
    });

    test('vencido el plazo no recuerda si el respaldo es reciente', () {
      expect(
          recordar(pospuestoHasta: '2026-10-03', ultimoRespaldo: '2026-10-01'),
          isFalse);
    });
  });

  // Chile cambia la hora a medianoche: dias de 23 o 25 horas. DayKey
  // cuenta dias calendario, asi que los limites no se corren.
  group('cambios de horario de Chile', () {
    test('abril (2026-04-04/05): 29 dias no, 30 si', () {
      expect(recordar(today: '2026-04-08', ultimoRespaldo: '2026-03-10'),
          isFalse);
      expect(recordar(today: '2026-04-09', ultimoRespaldo: '2026-03-10'),
          isTrue);
    });

    test('septiembre (2026-09-05/06/07): 29 dias no, 30 si', () {
      expect(recordar(today: '2026-09-13', ultimoRespaldo: '2026-08-15'),
          isFalse);
      expect(recordar(today: '2026-09-14', ultimoRespaldo: '2026-08-15'),
          isTrue);
    });

    test('gracia que cruza el cambio de abril: 6 dias no, 7 si', () {
      expect(
          recordar(today: '2026-04-07', primerUso: '2026-04-01'), isFalse);
      expect(recordar(today: '2026-04-08', primerUso: '2026-04-01'), isTrue);
    });

    test('pospuesto que cruza el cambio de septiembre', () {
      expect(recordar(today: '2026-09-09', pospuestoHasta: '2026-09-10'),
          isFalse);
      expect(recordar(today: '2026-09-10', pospuestoHasta: '2026-09-10'),
          isTrue);
    });
  });
}
