import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:aura/utils/notifications.dart';

void main() {
  setUpAll(tzdata.initializeTimeZones);

  test('un nombre conocido se usa tal cual', () {
    expect(
        resolveTimeZoneLocation('America/Santiago', const Duration(hours: -3))
            .name,
        'America/Santiago');
  });

  test('alias antiguos que informan algunos telefonos existen', () {
    for (final name in [
      'America/Buenos_Aires',
      'Asia/Calcutta',
      'Europe/Kiev',
      'Etc/UTC',
    ]) {
      expect(resolveTimeZoneLocation(name, Duration.zero).name, name);
    }
  });

  test('un nombre desconocido usa Etc/GMT con el desfase (signo invertido)',
      () {
    expect(
        resolveTimeZoneLocation('GMT+03:00', const Duration(hours: 3)).name,
        'Etc/GMT-3');
    expect(
        resolveTimeZoneLocation('Marte/Olympus', const Duration(hours: -4))
            .name,
        'Etc/GMT+4');
  });

  test('sin nombre, desfase no entero o fuera de rango: UTC', () {
    expect(resolveTimeZoneLocation(null, Duration.zero), tz.UTC);
    expect(
        resolveTimeZoneLocation(
            'X/Y', const Duration(hours: 5, minutes: 30)),
        tz.UTC);
    expect(resolveTimeZoneLocation('X/Y', const Duration(hours: 15)), tz.UTC);
  });
}
