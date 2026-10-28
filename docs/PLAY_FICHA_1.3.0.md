# Textos para Google Play: Aura 1.3.0 (build 8)

Borrador para copiar en Play Console. Los límites de caracteres son los de Play:
título 30, descripción corta 80, descripción completa 4000, "novedades" 500.

## Novedades de esta versión (campo "What's new", máx. 500)

**Español (es-419 / es-ES)**

```
Novedades de Aura 1.3.0:
- Modo embarazo: semanas, días y fecha probable de parto, con las predicciones en pausa.
- Resumen en PDF para llevar a tu consulta médica.
- Widget en la pantalla de inicio, con una opción discreta que no muestra datos.
- Tema claro, oscuro o el del teléfono.
- Aura ahora también está en inglés.
- Recordatorio diario para registrar y recordatorio de anticonceptivo (opcionales).
- Estadísticas rediseñadas.
```

**English (en-US)**

```
New in Aura 1.3.0:
- Pregnancy mode: weeks, days and estimated due date, with predictions paused.
- PDF summary to take to your doctor's appointment.
- Home-screen widget, with a discreet option that shows no data.
- Light, dark or system theme.
- Aura is now available in English.
- Optional daily logging reminder and birth-control reminder.
- Redesigned statistics.
```

## Ficha en inglés (en-US)

**App name (máx. 30):** `Aura: Cycle Tracker`

**Short description (máx. 80):**

```
Private period tracker. Your data stays on your phone. No account, no ads.
```

**Full description:**

```
Aura is an Android app to log your menstrual cycle and see honest estimates of your phases. Your data stays on your phone: no account, no server, no ads and no analytics.

WHAT AURA DOES
- Log your period, flow, mood, symptoms and notes in a couple of taps.
- See your next period, ovulation and fertile window as a range with a confidence level, not a single date promised as certain.
- Understand your current phase and how regular your cycles are, with redesigned statistics.
- Pregnancy mode: weeks and days of pregnancy and an estimated due date from the first day of your last period. Predictions pause, and there are no celebratory messages: the same neutral text for any outcome.
- PDF summary for your doctor: cycle length, regularity, a chart and your last 12 cycles. It is built on your phone and only leaves it if you share it.
- Home-screen widget with your next period or your pregnancy weeks. A discreet option hides all data and only shows "Aura".
- Optional reminders: period coming, daily logging, and birth control (pill, patch, ring or injection). Notification text is generic unless you choose to show details.
- Light, dark or system theme. Available in English and Spanish.

PRIVATE BY DESIGN
- No account and no server. There is nothing to sign up for.
- No ads, no analytics, no tracking.
- Backups are optional and encrypted with a password only you know. Save the file wherever you want, or turn on automatic backup to your own Google Drive.
- Aura hides its preview in the recent-apps list and blocks screenshots by default (you can turn this off).
- You can delete all your data at any time.

IMPORTANT
Aura is not a medical device and is not a contraceptive method. Dates are estimates calculated from your past records and can be inaccurate, especially with irregular cycles. Talk to a health professional if you have any doubt.

Built by an independent developer. Source code and documentation: https://github.com/Soofiaa/Aura
Privacy policy: https://soofiaa.github.io/Aura/privacy.html#en
```

## Seguridad de los datos (Data safety)

Datos tomados del código de 1.3.0: **no hay permisos nuevos** respecto de 1.2.0 (solo se
agregó el receptor del widget y la dependencia `pdf`, que corre en el teléfono). No hay
SDK de analítica, publicidad ni informes de fallos. Internet se usa solo si la usuaria
activa el respaldo en Drive.

| Pregunta del formulario | Respuesta sugerida | Por qué |
|---|---|---|
| ¿La app recopila o comparte datos de usuario? | **No** | Todo se procesa en el teléfono; el respaldo en Drive va cifrado con una contraseña que solo tiene la usuaria |
| ¿Se recopilan los datos cifrados / se pide borrado? | (no se muestra al responder "No") | Igual se mantiene el borrado en Ajustes |
| Política de privacidad | `https://soofiaa.github.io/Aura/privacy.html` | Ya cubre widget, PDF, embarazo y anticonceptivo |
| Mecanismo para pedir borrar datos | Sí: "Borrar todos los datos" en Ajustes o desinstalar | Documentado en la política |
| Publicidad / analítica | No | No hay ninguna |
| Compartir con terceros | No | El PDF y los respaldos solo salen por una acción de la usuaria (excepción "acción iniciada por el usuario") |

**Decisión tomada: declarar "No se recopilan datos" (opción 1).** El razonamiento de abajo
queda como respaldo por si Play pregunta. El único dato que
sale del teléfono sin que lo envíes tú a mano es el respaldo opcional en Google Drive.
Play define "recopilar" como transmitir datos fuera del dispositivo, y exime los datos con
cifrado de extremo a extremo que nadie más que quien envía y recibe puede leer. El
respaldo va cifrado con la contraseña de la usuaria y la desarrolladora no tiene la clave,
lo que encaja con la exención; pero la propia ayuda de Play dice que depende de la
implementación. Opciones:

1. **Declarar "no se recopilan datos"**, apoyándote en la exención. Es lo que describe mejor
   la app, pero si Play opina distinto, la ficha puede considerarse inexacta.
2. **Declarar Información de salud (Health info), opcional, cifrada en tránsito, finalidad
   "funcionalidad de la app", con borrado posible.** Más conservadora: nunca queda como
   inexacta, a costa de que la ficha muestre que la app recopila datos de salud.

Mi recomendación: la opción 2 si quieres cero riesgo de rechazo; la 1 si prefieres que
la ficha refleje que no hay servidor. Referencia: Play Console Help, artículo 10787469.

## Antes de subir a Play

- El `.aab` está firmado con la clave de subida correcta (SHA-256 `A9:32:D2:18:…:A8:2C`, el
  mismo de las versiones anteriores).
- Versión 1.3.0 (build 8). Play ya tiene 1.2.0 (build 7) en prueba interna.
- Las capturas de la ficha son de la versión anterior: conviene tomar nuevas del tema
  oscuro, el modo embarazo, el widget y las estadísticas.
