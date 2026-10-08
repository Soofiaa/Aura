/// Contrasena del respaldo cifrado (HU-06b, HU6b-3 y HU6b-4).
///
/// Los largos se miden en puntos de codigo Unicode (runes), no en bytes
/// ni en unidades UTF-16: "ñ" cuenta 1 y un emoji como "🌸" tambien 1.
/// No se normaliza el texto (HU6b-11).
library;

/// Largo minimo de la contrasena (HU6b-3).
const int minPasswordLength = 10;

/// Largo de [password] en puntos de codigo Unicode.
int passwordLength(String password) => password.runes.length;

/// Cumple el minimo de [minPasswordLength] puntos de codigo.
bool isPasswordLongEnough(String password) =>
    passwordLength(password) >= minPasswordLength;

enum PasswordStrength { weak, acceptable, strong }

extension PasswordStrengthLabel on PasswordStrength {
  String get label => switch (this) {
    PasswordStrength.weak => 'Débil',
    PasswordStrength.acceptable => 'Aceptable',
    PasswordStrength.strong => 'Fuerte',
  };
}

/// Orientacion simple de la fortaleza (HU6b-4). No bloquea nada: el unico
/// requisito es el largo minimo. Criterio:
///
/// 1. Menos de [minPasswordLength] puntos de codigo: debil.
/// 2. Un solo caracter repetido (por ejemplo "aaaaaaaaaaaa"): debil.
/// 3. Puntos: 1 desde 10, 2 desde 14 y 3 desde 18 puntos de codigo.
/// 4. +1 si usa al menos 3 clases de caracteres (minusculas, mayusculas,
///    digitos, espacios, otros).
/// 5. -1 si contiene una secuencia obvia de 4 o mas caracteres seguidos
///    que suben o bajan de a uno ("1234", "abcd", "dcba").
/// 6. -1 si son solo digitos.
/// 7. -1 si contiene una palabra de [_commonPasswordParts] ("password",
///    "contrasena", "qwerty"...), sin distinguir mayusculas ni tildes.
/// 8. -1 si termina en un anio 19xx o 20xx, con 0 a 2 simbolos despues
///    ("...2026", "...2026!", "...1999.").
/// 9. 3 o mas puntos: fuerte; 2: aceptable; menos: debil. Las
///    penalizaciones se acumulan y el resultado nunca baja de debil.
PasswordStrength passwordStrength(String password) {
  final runes = password.runes.toList();
  if (runes.length < minPasswordLength) return PasswordStrength.weak;
  if (runes.every((r) => r == runes.first)) return PasswordStrength.weak;

  var score = 1;
  if (runes.length >= 14) score++;
  if (runes.length >= 18) score++;
  if (_classCount(password) >= 3) score++;
  if (_hasObviousSequence(runes)) score--;
  if (runes.every(_isDigit)) score--;
  if (_hasCommonPart(password)) score--;
  if (_endsWithYear.hasMatch(password)) score--;

  if (score >= 3) return PasswordStrength.strong;
  if (score == 2) return PasswordStrength.acceptable;
  return PasswordStrength.weak;
}

bool _isDigit(int r) => r >= 0x30 && r <= 0x39;

/// Partes de contrasenas que un atacante prueba primero. Van en minusculas
/// y sin tildes ("contrasena" cubre tambien "contraseña"). Para ampliar la
/// lista basta con agregar otra entrada.
const List<String> _commonPasswordParts = [
  'password',
  'contrasena',
  'qwerty',
  'asdf',
  'admin',
  'letmein',
  '123456',
  'abc123',
  'iloveyou',
  'aura',
];

bool _hasCommonPart(String password) {
  final lower = password.toLowerCase();
  final plain = _withoutAccents(lower);
  return _commonPasswordParts.any(
    (part) => lower.contains(part) || plain.contains(part),
  );
}

/// Quita tildes, dieresis y la tilde de la enie (en minusculas).
String _withoutAccents(String lower) {
  const from = 'áàâäéèêëíìîïóòôöúùûüñ';
  const to = 'aaaaeeeeiiiioooouuuun';
  final buffer = StringBuffer();
  for (final r in lower.runes) {
    final c = String.fromCharCode(r);
    final i = from.indexOf(c);
    buffer.write(i >= 0 ? to[i] : c);
  }
  return buffer.toString();
}

/// Termina en 19xx o 20xx con 0 a 2 simbolos ASCII de puntuacion despues.
final RegExp _endsWithYear = RegExp(r'(19|20)\d{2}[!-/:-@\[-`{-~]{0,2}$');

/// Clases: minusculas, mayusculas, digitos, espacios y otros (simbolos,
/// emoji, letras sin mayuscula). "ñ" y las vocales con tilde cuentan como
/// letras.
int _classCount(String password) {
  var lower = false, upper = false, digit = false, space = false, other = false;
  for (final r in password.runes) {
    final c = String.fromCharCode(r);
    if (_isDigit(r)) {
      digit = true;
    } else if (c.trim().isEmpty) {
      space = true;
    } else if (c.toLowerCase() != c.toUpperCase()) {
      if (c == c.toLowerCase()) {
        lower = true;
      } else {
        upper = true;
      }
    } else {
      other = true;
    }
  }
  return [lower, upper, digit, space, other].where((x) => x).length;
}

/// 4 o mas caracteres seguidos que suben o bajan de a uno, sin distinguir
/// mayusculas ("1234", "abcd", "DCBA").
bool _hasObviousSequence(List<int> runes) {
  final lower = String.fromCharCodes(runes).toLowerCase().runes.toList();
  var up = 1, down = 1;
  for (var i = 1; i < lower.length; i++) {
    up = lower[i] == lower[i - 1] + 1 ? up + 1 : 1;
    down = lower[i] == lower[i - 1] - 1 ? down + 1 : 1;
    if (up >= 4 || down >= 4) return true;
  }
  return false;
}
