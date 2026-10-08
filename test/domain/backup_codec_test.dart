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

/// test/fixtures/backup_v4.json: respaldo v4 con datos inventados (un
/// cierre inferred, uno declared y una duracion habitual distinta de 5).
String _fixtureV4Text() => File('test/fixtures/backup_v4.json')
    .readAsStringSync()
    .replaceAll('\r\n', '\n');

Map<String, dynamic> _fixtureV4Map() =>
    jsonDecode(_fixtureV4Text()) as Map<String, dynamic>;

/// test/fixtures/backup_v5.json: el mismo contenido que backup_v4.json en
/// schema 5, con "Mostrar ovulacion y ventana fertil" apagado.
String _fixtureV5Text() => File('test/fixtures/backup_v5.json')
    .readAsStringSync()
    .replaceAll('\r\n', '\n');

Map<String, dynamic> _fixtureV5Map() =>
    jsonDecode(_fixtureV5Text()) as Map<String, dynamic>;

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

    test('no trae period_end y la duracion habitual queda en 5', () {
      final data = _expectSuccess(decodeBackup(utf8.encode(_fixtureText())));
      expect(data.days.map((d) => d.periodEnd), everyElement(isNull));
      expect(data.settings.typicalPeriodLength, 5);
    });

    test(
        'al volver a codificarlo sale en el formato actual, con los mismos '
        'datos', () {
      final data = _expectSuccess(decodeBackup(utf8.encode(_fixtureText())));
      final again =
          _expectSuccess(decodeBackup(utf8.encode(encodeBackup(data))));
      expect(again.days, data.days);
      expect(again.settings, data.settings);
    });
  });

  group('fixture backup_v4.json', () {
    test('se importa con period_end y la duracion habitual', () {
      final data =
          _expectSuccess(decodeBackup(utf8.encode(_fixtureV4Text())));
      expect(data.schemaVersion, 4);
      expect(data.days, hasLength(8));
      expect(data.symptomCount, 3);
      expect(
        {
          for (final d in data.days)
            if (d.periodEnd != null) d.date: d.periodEnd,
        },
        {
          '2026-06-05': PeriodEndSource.inferred,
          '2026-07-02': PeriodEndSource.declared,
        },
      );
      expect(data.settings.typicalPeriodLength, 4);
      expect(data.settings.reminderHour, 8);
    });

    test('ida y vuelta exacta: decodificar y volver a codificar da el mismo '
        'texto, byte a byte', () {
      final text = _fixtureV4Text();
      final data = _expectSuccess(decodeBackup(utf8.encode(text)));
      expect(encodeBackup(data), text);
    });
  });

  group('validacion v4', () {
    void expectDamagedV4(void Function(Map<String, dynamic> map) change) {
      final map = _fixtureV4Map();
      change(map);
      _expectFailure(_decodeMap(map), BackupError.damaged);
    }

    test('periodEnd desconocido',
        () => expectDamagedV4((m) => _firstDay(m)['periodEnd'] = 'pronto'));
    test('periodEnd en un dia sin sangrado', () {
      expectDamagedV4((m) {
        final day = (((m['data'] as Map)['dailyLogs'] as List)[6]) as Map;
        expect(day['isPeriodDay'], isFalse);
        day['periodEnd'] = 'declared';
      });
    });
    test('falta la clave periodEnd',
        () => expectDamagedV4((m) => _firstDay(m).remove('periodEnd')));
    test('falta typicalPeriodLength', () {
      expectDamagedV4((m) => _settings(m).remove('typicalPeriodLength'));
    });
    test('typicalPeriodLength 0',
        () => expectDamagedV4((m) => _settings(m)['typicalPeriodLength'] = 0));
    test('typicalPeriodLength 16',
        () => expectDamagedV4((m) => _settings(m)['typicalPeriodLength'] = 16));
    test('typicalPeriodLength no entero', () {
      expectDamagedV4((m) => _settings(m)['typicalPeriodLength'] = '5');
    });
    test('acepta typicalPeriodLength 1 y 15', () {
      for (final valid in [1, 15]) {
        final map = _fixtureV4Map();
        _settings(map)['typicalPeriodLength'] = valid;
        expect(_expectSuccess(_decodeMap(map)).settings.typicalPeriodLength,
            valid);
      }
    });
    test(
        'un respaldo v3 con una clave periodEnd la ignora (clave '
        'desconocida en v3)', () {
      final map = _fixtureMap();
      _firstDay(map)['periodEnd'] = 'declared';
      _settings(map)['typicalPeriodLength'] = 9;
      final data = _expectSuccess(_decodeMap(map));
      expect(data.days.first.periodEnd, isNull);
      expect(data.settings.typicalPeriodLength, 5);
    });
  });

  group('upgradeBackupData (respaldo v3 -> v4, regla D-2)', () {
    BackupData v3With(List<BackupDay> days) => BackupData(
          schemaVersion: 3,
          appVersion: '1.0.1',
          exportedAt: '2026-10-04T10:15:00-03:00',
          days: days,
          settings: const BackupSettings(
            onboardingSeen: true,
            notificationsEnabled: false,
            periodReminderEnabled: true,
            fertileWindowRemindersEnabled: false,
            showDetailsEnabled: false,
            reminderHour: 9,
            reminderMinute: 0,
          ),
        );
    BackupDay p(String date) =>
        BackupDay(date: date, isPeriodDay: true, periodDayExplicit: false);

    test('fixture v3: pasa a schema 4 sin ningun cierre (H-5)', () {
      final v3 = _expectSuccess(decodeBackup(utf8.encode(_fixtureText())));
      final v4 = upgradeBackupData(v3, today: '2026-10-04');
      expect(v4.schemaVersion, currentBackupSchemaVersion);
      expect(v4.days, v3.days);
      expect(v4.settings, v3.settings);
      expect(v4.appVersion, v3.appVersion);
      expect(v4.exportedAt, v3.exportedAt);
    });

    test('cierra con inferred solo el ultimo dia de los periodos que cumplen '
        'D-2, sin cambiar ningun otro dato', () {
      final v3 = v3With([
        BackupDay(
          date: '2026-08-01',
          isPeriodDay: true,
          periodDayExplicit: false,
          flow: FlowIntensity.moderado,
          symptoms: const [Symptom.acne],
        ),
        BackupDay(
          date: '2026-08-02',
          isPeriodDay: true,
          periodDayExplicit: false,
          flow: FlowIntensity.ligero,
          mood: Mood.feliz,
          notes: 'nota',
          symptoms: const [Symptom.cansancio],
        ),
        p('2026-09-01'), // un solo dia: abierto
      ]);
      final v4 = upgradeBackupData(v3, today: '2026-10-07');
      expect(v4.days[1], v3.days[1].withPeriodEnd(PeriodEndSource.inferred));
      expect(v4.days[0], v3.days[0]);
      expect(v4.days[2], v3.days[2]);
    });

    test('"hoy" decide si el periodo mas reciente puede seguir', () {
      final v3 = v3With([p('2026-09-28'), p('2026-09-29')]);
      expect(
          upgradeBackupData(v3, today: '2026-10-06')
              .days
              .map((d) => d.periodEnd),
          [null, null]);
      expect(
          upgradeBackupData(v3, today: '2026-10-07')
              .days
              .map((d) => d.periodEnd),
          [null, PeriodEndSource.inferred]);
    });

    test('un respaldo del schema actual se devuelve sin cambios', () {
      final v5 = _expectSuccess(decodeBackup(utf8.encode(_fixtureV5Text())));
      expect(identical(upgradeBackupData(v5, today: '2026-10-07'), v5),
          isTrue);
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
          schemaVersion: currentBackupSchemaVersion,
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

  // HU-05, CP5a: schema 5 ("Mostrar ovulacion y ventana fertil").
  group('HU-05 CP5a - respaldo v5', () {
    test('fixture v5: se importa con el interruptor apagado y el resto igual '
        'que el v4', () {
      final v5 = _expectSuccess(decodeBackup(utf8.encode(_fixtureV5Text())));
      final v4 = _expectSuccess(decodeBackup(utf8.encode(_fixtureV4Text())));
      expect(v5.schemaVersion, 5);
      expect(v5.settings.showFertileWindow, isFalse);
      expect(v5.days, v4.days);
      expect(v5.settings.typicalPeriodLength, v4.settings.typicalPeriodLength);
    });

    test('fixture v5: ida y vuelta exacta, byte a byte', () {
      final text = _fixtureV5Text();
      expect(encodeBackup(_expectSuccess(decodeBackup(utf8.encode(text)))),
          text);
    });

    test('ida y vuelta con el interruptor en true y en false', () {
      final base =
          _expectSuccess(decodeBackup(utf8.encode(_fixtureV5Text())));
      for (final value in [true, false]) {
        final s = base.settings;
        final data = BackupData(
          schemaVersion: currentBackupSchemaVersion,
          appVersion: base.appVersion,
          exportedAt: base.exportedAt,
          days: base.days,
          settings: BackupSettings(
            onboardingSeen: s.onboardingSeen,
            notificationsEnabled: s.notificationsEnabled,
            periodReminderEnabled: s.periodReminderEnabled,
            fertileWindowRemindersEnabled: s.fertileWindowRemindersEnabled,
            showDetailsEnabled: s.showDetailsEnabled,
            reminderHour: s.reminderHour,
            reminderMinute: s.reminderMinute,
            typicalPeriodLength: s.typicalPeriodLength,
            showFertileWindow: value,
          ),
        );
        final again =
            _expectSuccess(decodeBackup(utf8.encode(encodeBackup(data))));
        expect(again.settings.showFertileWindow, value);
        expect(again.settings, data.settings);
        expect(again.days, data.days);
      }
    });

    test('v3 y v4 se restauran con true (aunque traigan la clave)', () {
      final v3Map = _fixtureMap();
      final v4Map = _fixtureV4Map();
      for (final map in [v3Map, v4Map]) {
        expect(_expectSuccess(_decodeMap(map)).settings.showFertileWindow,
            isTrue);
        _settings(map)['showFertileWindow'] = false;
        expect(_expectSuccess(_decodeMap(map)).settings.showFertileWindow,
            isTrue);
      }
    });

    test('upgradeBackupData: v4 pasa a schema 5 sin tocar dias ni ajustes',
        () {
      final v4 = _expectSuccess(decodeBackup(utf8.encode(_fixtureV4Text())));
      final up = upgradeBackupData(v4, today: '2026-10-07');
      expect(up.schemaVersion, 5);
      expect(up.days, v4.days);
      expect(up.settings, v4.settings);
      expect(up.settings.showFertileWindow, isTrue);
      expect(up.appVersion, v4.appVersion);
      expect(up.exportedAt, v4.exportedAt);
    });

    test('upgradeBackupData: v3 pasa a schema 5 con true', () {
      final v3 = _expectSuccess(decodeBackup(utf8.encode(_fixtureText())));
      final up = upgradeBackupData(v3, today: '2026-10-04');
      expect(up.schemaVersion, 5);
      expect(up.settings.showFertileWindow, isTrue);
    });

    test('un v4 se sigue escribiendo como v4 (sin la clave nueva)', () {
      final text = _fixtureV4Text();
      final again =
          encodeBackup(_expectSuccess(decodeBackup(utf8.encode(text))));
      expect(again, text);
      expect(again, isNot(contains('showFertileWindow')));
    });

    test('v5 sin showFertileWindow: danado', () {
      final map = _fixtureV5Map();
      _settings(map).remove('showFertileWindow');
      _expectFailure(_decodeMap(map), BackupError.damaged);
    });

    test('v5 con showFertileWindow no booleano: danado', () {
      for (final bad in [1, 'false', null]) {
        final map = _fixtureV5Map();
        _settings(map)['showFertileWindow'] = bad;
        _expectFailure(_decodeMap(map), BackupError.damaged);
      }
    });

    test('un schema posterior al actual (6) se rechaza como version mas '
        'nueva, igual que la v4 rechaza un v5', () {
      final map = _fixtureV5Map()..['schemaVersion'] = 6;
      _expectFailure(_decodeMap(map), BackupError.newerVersion);
    });
  });
}
