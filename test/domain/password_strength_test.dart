import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:aura/domain/password_strength.dart';

/// HU-06b CP3: largo minimo en puntos de codigo y orientacion de
/// fortaleza (HU6b-3, HU6b-4). Contrasenas inventadas.
void main() {
  group('largo en puntos de codigo, no en bytes', () {
    test('"contrase\u00f1a": 10 puntos de codigo, 11 bytes UTF-8', () {
      expect(utf8.encode('contrase\u00f1a').length, 11);
      expect(passwordLength('contrase\u00f1a'), 10);
      expect(isPasswordLongEnough('contrase\u00f1a'), isTrue);
    });

    test('nueve "ñ": 18 bytes pero solo 9 puntos de codigo, no alcanza', () {
      const p = '\u00f1\u00f1\u00f1\u00f1\u00f1\u00f1\u00f1\u00f1\u00f1';
      expect(utf8.encode(p).length, 18);
      expect(passwordLength(p), 9);
      expect(isPasswordLongEnough(p), isFalse);
    });

    test('emoji: cada uno cuenta 1 (no 2 unidades UTF-16 ni 4 bytes)', () {
      const p = '🌸🌸🌸🌸🌸abcd';
      expect(p.length, 14);
      expect(passwordLength(p), 9);
      expect(isPasswordLongEnough(p), isFalse);
      expect(isPasswordLongEnough('${p}e'), isTrue);
    });
  });

  group('niveles', () {
    final cases = <String, PasswordStrength>{
      '': PasswordStrength.weak,
      'corta': PasswordStrength.weak,
      // 10 (1 punto), 1 clase, palabra comun (-1).
      'contrase\u00f1a': PasswordStrength.weak,
      // 15 (2 puntos) con 2 clases.
      'mi casa es azul': PasswordStrength.acceptable,
      // 12 (1 punto) + 3 clases (mayusculas, minusculas, espacios).
      'Axbq eqzh ij': PasswordStrength.acceptable,
      // 19 (3 puntos).
      'mi casa es muy azul': PasswordStrength.strong,
      // 14 (2) + 5 clases (1) - termina en un anio (1).
      'Gato-Luna 2026': PasswordStrength.acceptable,
      // Frase larga de palabras comunes, sin esos patrones: 29 (3).
      'el perro come pan en la plaza': PasswordStrength.strong,
    };
    cases.forEach((password, expected) {
      test('"$password" -> ${expected.label}', () {
        expect(passwordStrength(password), expected);
      });
    });

    test('etiquetas en espanol', () {
      expect(PasswordStrength.weak.label, 'D\u00e9bil');
      expect(PasswordStrength.acceptable.label, 'Aceptable');
      expect(PasswordStrength.strong.label, 'Fuerte');
    });
  });

  group('penalizaciones', () {
    test('un solo caracter repetido: debil aunque sea largo', () {
      expect(passwordStrength('a' * 30), PasswordStrength.weak);
      expect(passwordStrength('\u00f1' * 20), PasswordStrength.weak);
    });

    test('secuencia obvia ascendente o descendente: baja un nivel', () {
      expect(passwordStrength('mi casa es azul'), PasswordStrength.acceptable);
      expect(passwordStrength('mi casa es abcd'), PasswordStrength.weak);
      expect(passwordStrength('mi casa es dcba'), PasswordStrength.weak);
      expect(
        passwordStrength('mi casa es 1234'),
        PasswordStrength.acceptable,
        reason: '15 (2) + 3 clases (1) - secuencia (1) = 2',
      );
      expect(passwordStrength('mi casa es 1357'), PasswordStrength.strong);
    });

    test('solo digitos: baja un nivel', () {
      expect(passwordStrength('9182736455'), PasswordStrength.weak);
      expect(
        passwordStrength('918273645591827364'),
        PasswordStrength.acceptable,
        reason: '18 (3) - solo digitos (1) = 2',
      );
      expect(
        passwordStrength('12345678901234567890'),
        PasswordStrength.weak,
        reason: '20 (3) - secuencia (1) - solo digitos (1) - "123456" (1)',
      );
    });
  });

  group('patrones que un atacante prueba primero', () {
    test(
      '"Contrase\u00f1a2026!": de fuerte a debil (palabra comun y anio)',
      () {
        // 15 (2) + 4 clases (1) - palabra (1) - anio (1) = 1.
        expect(passwordStrength('Contrase\u00f1a2026!'), PasswordStrength.weak);
      },
    );

    test('"Password2026!": debil', () {
      // 13 (1) + 4 clases (1) - palabra (1) - anio (1) = 0.
      expect(passwordStrength('Password2026!'), PasswordStrength.weak);
    });

    test('palabra comun, sin distinguir mayusculas ni tildes', () {
      // Mismo largo (22) y clases: solo cambia la palabra.
      expect(
        passwordStrength('MI CLAVESITA ES LARGA'),
        PasswordStrength.strong,
      );
      expect(
        passwordStrength('MI CONTRASE\u00d1A ES LARGA'),
        PasswordStrength.acceptable,
      );
      expect(
        passwordStrength('MI CONTRASENA ES LARGA'),
        PasswordStrength.acceptable,
      );
      expect(
        passwordStrength('mi teclado azul viejo'),
        PasswordStrength.strong,
      );
      expect(
        passwordStrength('mi teclado qwerty viejo'),
        PasswordStrength.acceptable,
      );
    });

    test('anio al final, con 0 a 2 simbolos despues', () {
      expect(
        passwordStrength('mi gato 2026 luna'),
        PasswordStrength.strong,
        reason: 'el anio no esta al final',
      );
      expect(
        passwordStrength('mi gato luna 2026'),
        PasswordStrength.acceptable,
      );
      expect(passwordStrength('mi gat lu 2026!'), PasswordStrength.acceptable);
      expect(passwordStrength('mi gat lu 2026!!'), PasswordStrength.acceptable);
      expect(passwordStrength('mi gat lu 1999.'), PasswordStrength.acceptable);
      expect(
        passwordStrength('mi gat lu 2026!!!'),
        PasswordStrength.strong,
        reason: 'con 3 simbolos ya no cuenta como "termina en un anio"',
      );
    });

    test('las penalizaciones se acumulan y nunca baja de debil', () {
      // 20 (3) - secuencia (1) - solo digitos (1) - "123456" (1) = 0.
      expect(passwordStrength('12345678901234567890'), PasswordStrength.weak);
      expect(passwordStrength('password2026'), PasswordStrength.weak);
    });
  });
}
