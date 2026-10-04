import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:aura/data/models/day_enums.dart';
import 'package:aura/domain/backup_codec.dart';

/// test/fixtures/backup_v3.json es un respaldo v3 escrito a mano. NUNCA
/// se modifica: toda version futura de Aura debe seguir importandolo.
/// Se normaliza CRLF -> LF porque git puede convertirlo al hacer checkout
/// en Windows (core.autocrlf); encodeBackup siempre escribe LF.
String _fixtureText() => File('test/fixtures/backup_v3.json')
    .readAsStringSync()
    .replaceAll('\r\n', '\n');

Map<String, dynamic> _fixtureMap() =>
    jsonDecode(_fixtureText()) as Map<String, dynamic>;

List<int> _bytes(Object json) => utf8.encode(jsonEncode(json));

BackupParseResult _decodeMap(Map<String, dynamic> map) =>
    decodeBackup(_bytes(map));

Map<String, dynamic> _firstDay(Map<String, dynamic> map) =>
    ((map['data'] as Map)['dailyLogs'] as List).first as Map<String, dynamic>;

Map<String, dynamic> _settings(Map<String, dynamic> map) =>
    (map['data'] as Map)['settings'] as Map<String, dynamic>;

BackupData _expectSuccess(BackupParseResult result) {
  expect(result, isA<BackupParseSuccess>(), reason: '$result');
  return (result as BackupParseSuccess).data;
}

void _expectFailure(BackupParseResult result, BackupError error) {
  expect(result, isA<BackupParseFailure>());
  expect((result as BackupParseFailure).error, error, reason: result.detail);
}

void main() {
  group('fixture backup_v3.json', () {
    test('se importa con todos sus datos', () {
      final data = _expectSuccess(decodeBackup(utf8.encode(_fixtureText())));

      expect(data.schemaVersion, 3);
      expect(data.appVersion, '1.1.0');
      expect(data.exportedAt, '2026-10-04T10:15:00-03:00');
      expect(data.days, hasLength(7));
      expect(data.symptomCount, 9);

      final dia29 = data.days[1];
      expect(dia29.date, '2026-08-29');
      expect(dia29.flow, FlowIntensity.abundante);
      expect(dia29.mood, isNull);
      expect(dia29.notes, 'Día difícil 😣\nTomé "ibuprofeno"');
      expect(dia29.symptoms,
          [Symptom.dolorAbdominal, Symptom.dolorDeEspalda]);

      expect(data.days[3].notes, '', reason: 'nota vacia no es null');
      expect(data.days[4].isPeriodDay, isFalse);
      expect(data.days[4].periodDayExplicit, isTrue);

      expect(
        data.settings,
        const BackupSettings(
          onboardingSeen: true,
          notificationsEnabled: true,
          periodReminderEnabled: false,
          fertileWindowRemindersEnabled: true,
          showDetailsEnabled: true,
          reminderHour: 21,
          reminderMinute: 30,
        ),
      );
    });

    test('ida y vuelta exacta: decodificar y volver a codificar da el mismo '
        'texto, byte a byte', () {
      final text = _fixtureText();
      final data = _expectSuccess(decodeBackup(utf8.encode(text)));
      expect(encodeBackup(data), text);
    });
  });

  group('exportacion determinista', () {
    BackupDay day(String date, List<Symptom> symptoms) => BackupDay(
          date: date,
          isPeriodDay: false,
          periodDayExplicit: false,
          symptoms: symptoms,
        );

    const settings = BackupSettings(
      onboardingSeen: true,
      notificationsEnabled: false,
      periodReminderEnabled: true,
      fertileWindowRemindersEnabled: false,
      showDetailsEnabled: false,
      reminderHour: 9,
      reminderMinute: 0,
    );

    BackupData dataWith(List<BackupDay> days) => BackupData(
          schemaVersion: 3,
          appVersion: '1.0.1',
          exportedAt: '2026-10-04T10:15:00-03:00',
          days: days,
          settings: settings,
        );

    test('el orden de entrada de dias y sintomas no cambia el texto', () {
      final ordenado = dataWith([
        day('2026-01-01', [Symptom.acne, Symptom.cansancio]),
        day('2026-01-02', []),
        day('2026-01-10', [Symptom.antojos, Symptom.hinchazon]),
      ]);
      final desordenado = dataWith([
        day('2026-01-10', [Symptom.hinchazon, Symptom.antojos]),
        day('2026-01-01', [Symptom.cansancio, Symptom.acne]),
        day('2026-01-02', []),
      ]);

      expect(encodeBackup(desordenado), encodeBackup(ordenado));
    });

    test('decodificar lo codificado devuelve los mismos datos', () {
      final original = dataWith([
        day('2026-01-01', [Symptom.acne, Symptom.cansancio]),
        day('2026-01-02', []),
      ]);
      final data =
          _expectSuccess(decodeBackup(utf8.encode(encodeBackup(original))));
      expect(data.days, original.days);
      expect(data.settings, original.settings);
      expect(data.exportedAt, original.exportedAt);
    });

    test('los sintomas desordenados en el archivo quedan ordenados', () {
      final map = _fixtureMap();
      _firstDay(map)['symptoms'] = ['dolorAbdominal', 'cansancio'];
      final data = _expectSuccess(_decodeMap(map));
      expect(data.days.first.symptoms,
          [Symptom.cansancio, Symptom.dolorAbdominal]);
    });
  });

  group('formatExportedAt', () {
    test('incluye el desfase de zona y representa el mismo instante', () {
      final now = DateTime(2026, 10, 4, 10, 15, 7);
      final text = formatExportedAt(now);

      expect(text, matches(r'^2026-10-04T10:15:07[+-]\d{2}:\d{2}$'));
      expect(DateTime.parse(text).toUtc(), now.toUtc());
    });
  });

  group('rechazos: no es un respaldo de Aura', () {
    test('archivo vacio', () {
      _expectFailure(decodeBackup([]), BackupError.notABackup);
    });

    test('texto que no es JSON', () {
      _expectFailure(
          decodeBackup(utf8.encode('hola')), BackupError.notABackup);
    });

    test('bytes que no son UTF-8', () {
      _expectFailure(decodeBackup([0xff, 0xfe, 0x00]), BackupError.notABackup);
    });

    test('JSON que no es un objeto', () {
      _expectFailure(decodeBackup(_bytes([1, 2])), BackupError.notABackup);
    });

    test('objeto sin format o con otro format', () {
      final sinFormat = _fixtureMap()..remove('format');
      _expectFailure(_decodeMap(sinFormat), BackupError.notABackup);

      final otro = _fixtureMap()..['format'] = 'petpal_full_zip_backup_v3';
      _expectFailure(_decodeMap(otro), BackupError.notABackup);
    });
  });

  test('archivo de mas de 5 MB se rechaza sin parsear', () {
    _expectFailure(
        decodeBackup(List.filled(maxBackupSizeBytes + 1, 0x20)),
        BackupError.tooLarge);
  });

  group('rechazos: version mas nueva', () {
    test('schemaVersion posterior a la actual', () {
      final map = _fixtureMap()
        ..['schemaVersion'] = currentBackupSchemaVersion + 1;
      _expectFailure(_decodeMap(map), BackupError.newerVersion);
    });

    test('formatVersion posterior', () {
      final map = _fixtureMap()..['formatVersion'] = backupFormatVersion + 1;
      _expectFailure(_decodeMap(map), BackupError.newerVersion);
    });

    test('respaldo cifrado (HU-06b todavia no existe)', () {
      final map = _fixtureMap()
        ..['encryption'] = {'kdf': 'pbkdf2-sha256'};
      _expectFailure(_decodeMap(map), BackupError.newerVersion);
    });
  });

  group('rechazos: respaldo danado', () {
    void expectDamaged(void Function(Map<String, dynamic> map) mutate) {
      final map = _fixtureMap();
      mutate(map);
      _expectFailure(_decodeMap(map), BackupError.damaged);
    }

    test('archivo de Aura cortado a la mitad', () {
      final bytes = utf8.encode(_fixtureText());
      _expectFailure(decodeBackup(bytes.sublist(0, bytes.length ~/ 2)),
          BackupError.damaged);
    });

    test('schemaVersion anterior a la primera que exporta', () {
      expectDamaged((m) => m['schemaVersion'] = minBackupSchemaVersion - 1);
    });

    test('formatVersion 0', () => expectDamaged((m) => m['formatVersion'] = 0));
    test('falta encryption', () => expectDamaged((m) => m.remove('encryption')));
    test('schemaVersion no numerico',
        () => expectDamaged((m) => m['schemaVersion'] = '3'));
    test('exportedAt invalido',
        () => expectDamaged((m) => m['exportedAt'] = 'ayer'));
    test('falta data', () => expectDamaged((m) => m.remove('data')));
    test('falta settings',
        () => expectDamaged((m) => (m['data'] as Map).remove('settings')));
    test('un dia que no es objeto', () {
      expectDamaged(
          (m) => ((m['data'] as Map)['dailyLogs'] as List).add('2026-01-01'));
    });

    test('fecha sin ceros a la izquierda',
        () => expectDamaged((m) => _firstDay(m)['date'] = '2026-8-28'));
    test('fecha que no existe en el calendario',
        () => expectDamaged((m) => _firstDay(m)['date'] = '2026-02-30'));
    test('fecha repetida', () {
      expectDamaged((m) {
        final logs = (m['data'] as Map)['dailyLogs'] as List;
        logs.add(Map<String, dynamic>.from(logs.first as Map));
        (m['counts'] as Map)['dailyLogs'] = logs.length;
        (m['counts'] as Map)['symptoms'] = 11;
      });
    });

    test('flujo en un dia sin sangrado', () {
      expectDamaged((m) => _firstDay(m)['isPeriodDay'] = false);
    });
    test('flujo desconocido',
        () => expectDamaged((m) => _firstDay(m)['flow'] = 'medio'));
    test('animo desconocido',
        () => expectDamaged((m) => _firstDay(m)['mood'] = 'contenta'));
    test('falta la clave mood',
        () => expectDamaged((m) => _firstDay(m).remove('mood')));
    test('isPeriodDay no booleano',
        () => expectDamaged((m) => _firstDay(m)['isPeriodDay'] = 1));
    test('sintoma desconocido', () {
      expectDamaged((m) => _firstDay(m)['symptoms'] = ['cansancio', 'fiebre']);
    });
    test('sintoma repetido', () {
      expectDamaged(
          (m) => _firstDay(m)['symptoms'] = ['cansancio', 'cansancio']);
    });
    test('falta la clave notes',
        () => expectDamaged((m) => _firstDay(m).remove('notes')));
    test('notes no es texto',
        () => expectDamaged((m) => _firstDay(m)['notes'] = 42));

    test('hora 24', () => expectDamaged((m) => _settings(m)['reminderHour'] = 24));
    test('minuto 60',
        () => expectDamaged((m) => _settings(m)['reminderMinute'] = 60));
    test('hora negativa',
        () => expectDamaged((m) => _settings(m)['reminderHour'] = -1));
    test('ajuste booleano como texto', () {
      expectDamaged((m) => _settings(m)['periodReminderEnabled'] = 'true');
    });

    test('counts de dias no coincide (dias perdidos)', () {
      expectDamaged(
          (m) => ((m['data'] as Map)['dailyLogs'] as List).removeLast());
    });
    test('counts de sintomas no coincide', () {
      expectDamaged((m) => _firstDay(m)['symptoms'] = ['cansancio']);
    });
    test('falta counts', () => expectDamaged((m) => m.remove('counts')));
  });

  group('rango de fechas', () {
    BackupParseResult withDate(String date, {String? exportedAt}) {
      final map = _fixtureMap();
      _firstDay(map)['date'] = date;
      if (exportedAt != null) map['exportedAt'] = exportedAt;
      return _decodeMap(map);
    }

    test('acepta el limite inferior 1970-01-01 y rechaza el dia anterior', () {
      _expectSuccess(withDate('1970-01-01'));
      _expectFailure(withDate('1969-12-31'), BackupError.damaged);
    });

    test('acepta fechas futuras hasta 2030-12-31 (formulario v1.0) aunque '
        'el respaldo sea de 2026', () {
      _expectSuccess(withDate('2030-12-31'));
      _expectFailure(withDate('2031-01-01'), BackupError.damaged);
    });

    test('con un reloj posterior a 2030, el tope es la fecha de exportacion '
        'mas 2 dias', () {
      const exportedAt = '2099-03-10T08:00:00+01:00';
      _expectSuccess(withDate('2099-03-12', exportedAt: exportedAt));
      _expectFailure(
          withDate('2099-03-13', exportedAt: exportedAt), BackupError.damaged);
    });

    test('el rechazo por rango informa la fecha como dato estructurado', () {
      final result = withDate('2031-01-01') as BackupParseFailure;
      expect(result.error, BackupError.damaged);
      expect(result.outOfRangeDate, '2031-01-01');
    });

    test('otros rechazos no informan fecha fuera de rango', () {
      final result = withDate('2026-02-30') as BackupParseFailure;
      expect(result.outOfRangeDate, isNull);
    });

    test('rechaza basura como el ano 0001 o 9999', () {
      _expectFailure(withDate('0001-01-01'), BackupError.damaged);
      _expectFailure(withDate('9999-12-31'), BackupError.damaged);
    });
  });

  test('ignora claves desconocidas dentro de la misma version', () {
    final map = _fixtureMap()..['comentario'] = 'agregado a mano';
    _firstDay(map)['extra'] = true;
    _expectSuccess(_decodeMap(map));
  });
}
