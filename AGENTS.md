# AGENTS.md — Aura

App de registro de ciclos para Android. Flutter + Drift/SQLite esquema v6.
Versión en prueba cerrada en Google Play: 1.3.0+9. Repo: Soofiaa/Aura.

## SDK — obligatorio

Usa SIEMPRE C:\tools\flutter-3.44.9\flutter\bin\flutter.bat
(Flutter 3.44.9, Dart 3.12.2).
NO uses el Flutter 3.22.0 del PATH ni el 3.47.9 de
C:\tools\flutter-sdk2\flutter: con 3.47.9
`flutter pub get --enforce-lockfile` falla (exit 65) porque el SDK
exige intl 0.20.3, matcher 0.12.20, meta 1.19.0, test_api 0.7.12 y
vector_math 2.4.4, distintos de los pines del lockfile.
Si --enforce-lockfile falla, detente y reporta el error exacto.
Nunca regeneres pubspec.lock.

## Regla de evidencia — aplica a todos los reportes. No omitir nunca.

1. No afirmes ningún commit, push, corrida de CI, conteo de tests ni
   cambio de archivo sin pegar la salida exacta del comando que lo produjo.
2. Si un comando no se ejecutó, escribe literalmente "no ejecutado" —
   nunca inventes su resultado, su SHA, su URL ni su número.
3. Antes de reportar, corre y pega: git status, git log --oneline -5,
   git branch --show-current y git diff --stat.
4. Un run de CI solo existe si pegas su URL real después de que terminó,
   con el resultado real. Una URL inventada o un 404 no es evidencia.
5. Si un comando falla, pega el error exacto y detente. No regeneres
   pubspec.lock, no cambies de versión ni corrijas en silencio.
6. Si tu reporte anterior y git status no coinciden en la lista de
   archivos, explica la diferencia archivo por archivo antes de commitear.

## Estado (2026-11-12)

- Fase 1 completa: CI en .github/workflows/ci.yml (Flutter 3.44.9,
  windows-latest, pub get --enforce-lockfile + analyze + test).
- Fase 2 completa: commit 5f9c0d0, sin ventana fértil ni ovulación con
  anticonceptivo hormonal activo. Tests locales 1379 (1375 + 4 nuevos);
  el conteo no se reconfirmó desde el log del CI.
- Data Safety: documentación en opción 2, commit b7976ad. La declaración
  en Play Console es manual de Sofia y queda pendiente.
- Manchado completo: commit "fix: un día aislado de flujo ligero no inicia
  un ciclo (manchado)". Regla única en groupPeriodRunsForCycles
  (derivación, período actual, cierre, rango, avisos, Calendario, hoja).
  Tests locales 1396 (1379 + 17 nuevos); el conteo no se reconfirmó desde
  el log del CI.
- Respaldo v7 completo: commit "feat: respaldo v7 incluye ajustes del
  dispositivo". La base y el respaldo pasan a v7; la migración 6 -> 7 no
  toca tablas. Todos los DeviceSettings viajan en el respaldo; un respaldo
  anterior o uno con la sección inválida conserva los ajustes del
  teléfono, y Deshacer los revierte. widgetDiscreto=true por defecto.
  Tests locales 1414 (1396 + 14 nuevos + 4 casos drift generados hacia
  v7); el conteo no se reconfirmó desde el log del CI.
- Siguiente: ampliar la prueba cerrada.

## Límites por defecto

No cambies la versión, pubspec.lock, lib/ ni .github/workflows/ci.yml
salvo que la fase lo pida explícitamente. No toques el modo embarazo
ni la lógica de ciclos salvo que la fase lo pida. Si un test falla,
repórtalo con nombre y archivo; no lo corrijas en silencio.
