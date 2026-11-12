# Textos para Google Play: Aura 1.3.0 (build 9)

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

**Decisión vigente (2026-11-12): opción 2.** Se declara que la app recopila **Información de
salud**, de forma **opcional**, **cifrada en tránsito**, con finalidad **"Funcionalidad de la
app"** y con **borrado posible**. Reemplaza a la opción 1 ("No se recopilan datos"), que
queda al final de esta sección como nota histórica.

**Estado: pendiente de ingresar.** La declaración se envía a mano en Play Console; este
documento solo deja los valores listos para copiar.

Por qué la opción 2: Play define "recopilar" como transmitir datos desde la app hacia fuera
del dispositivo, lleguen a quien lleguen. El respaldo automático en Drive (opcional, apagado
por defecto) sube un archivo con datos de salud a la cuenta de Google de la usuaria. Va
cifrado y ni la desarrolladora ni Google pueden leer su contenido, pero Google sí ve la
cuenta, el nombre del archivo (`aura_respaldo_automatico.json`, en la carpeta "Aura"), su
fecha y su tamaño. Declararlo nunca deja la ficha como inexacta. No declararlo dependía de
una exención que la propia ayuda de Play condiciona: "It depends on the particular
implementation". Referencia: Play Console Help, artículo 10787469, revisado el 2026-11-12.

### Valores a ingresar en Play Console

Los nombres de pantallas y opciones son los de la ayuda de Play en español (artículo
10787469). En la consola pueden variar un poco.

| Paso | Pantalla o pregunta | Valor |
|---|---|---|
| 1 | Play Console → Aura → **Contenido de la app** → **Seguridad de los datos** | **Iniciar** (o editar la declaración que ya exista) |
| 2 | Seguridad y recopilación de datos: ¿la app recopila o comparte alguno de los tipos de datos del usuario requeridos? | **Sí** |
| 3 | ¿Todos los datos del usuario que recopila la app se encriptan en tránsito? | **Sí** (HTTPS hacia `www.googleapis.com`; además el archivo ya sale cifrado del teléfono) |
| 4 | ¿Ofreces un método para que los usuarios soliciten que se borren sus datos? | **Sí** |
| 5 | Si pregunta si la app permite crear una cuenta | **No** (Aura no tiene cuentas propias; el inicio de sesión de Google solo autoriza el acceso a Drive) |
| 6 | Tipos de datos | Solo **Salud y fitness → Información de salud**. Ningún otro |
| 7 | Uso y manejo de datos (Información de salud): ¿se recopilan, se comparten o ambas cosas? | Solo **Recopilados** |
| 8 | ¿Estos datos se procesan de forma efímera? | **No** |
| 9 | ¿Los datos son necesarios para la app o los usuarios pueden decidir si se recopilan? | **Los usuarios pueden decidir si los datos se recopilan o no** |
| 10 | ¿Por qué se recopilan estos datos del usuario? | Solo **Funcionalidad de la app** |
| 11 | Política de privacidad | `https://soofiaa.github.io/Aura/privacy.html` |
| 12 | Vista previa de la ficha de Play Store | Revisar que coincida con lo de arriba y **Enviar** |

Notas para completar el formulario:

- **No se marca "Compartidos".** No hay publicidad ni analítica. El PDF y los respaldos
  manuales solo salen por una acción de la usuaria (excepción "acción iniciada por el
  usuario"), y el respaldo en Drive va a su propia cuenta porque ella lo activa.
- **Borrado (paso 4).** "Borrar todos los datos" en Ajustes borra lo del teléfono y
  desconecta Drive, pero **no** borra el archivo ya subido: la usuaria lo elimina desde su
  propio Drive. La desarrolladora no tiene copia ni acceso. Así lo dice la política.
- **Cuenta (paso 5).** El texto exacto de las preguntas de eliminación de cuenta no se pudo
  ver desde aquí. La respuesta se apoya en la definición de Play: una "cuenta de la app" es
  una identidad que entrega el desarrollador, y Aura no tiene ninguna.
- **Punto a confirmar.** El respaldo también lleva las notas de texto libre de cada día. Play
  lista "notas" bajo **Actividad en apps → Otro contenido generado por usuarios**. Aquí se
  declaran dentro de Información de salud; si se quiere la lectura más conservadora, se marca
  también ese tipo con las mismas respuestas de los pasos 7 a 10.

### Nota histórica: opción 1 (superada el 2026-11-12)

Hasta el 2026-11-12 este documento registraba la decisión contraria. Se conserva tal como
estaba, solo como historia; **ya no es la decisión vigente**.

> **Decisión tomada: declarar "No se recopilan datos" (opción 1).** El razonamiento de abajo
> queda como respaldo por si Play pregunta. El único dato que
> sale del teléfono sin que lo envíes tú a mano es el respaldo opcional en Google Drive.
> Play define "recopilar" como transmitir datos fuera del dispositivo, y exime los datos con
> cifrado de extremo a extremo que nadie más que quien envía y recibe puede leer. El
> respaldo va cifrado con la contraseña de la usuaria y la desarrolladora no tiene la clave,
> lo que encaja con la exención; pero la propia ayuda de Play dice que depende de la
> implementación. Opciones:
>
> 1. **Declarar "no se recopilan datos"**, apoyándote en la exención. Es lo que describe mejor
>    la app, pero si Play opina distinto, la ficha puede considerarse inexacta.
> 2. **Declarar Información de salud (Health info), opcional, cifrada en tránsito, finalidad
>    "funcionalidad de la app", con borrado posible.** Más conservadora: nunca queda como
>    inexacta, a costa de que la ficha muestre que la app recopila datos de salud.
>
> Mi recomendación: la opción 2 si quieres cero riesgo de rechazo; la 1 si prefieres que
> la ficha refleje que no hay servidor. Referencia: Play Console Help, artículo 10787469.

Con la opción 1 la respuesta a "¿La app recopila o comparte datos de usuario?" era **No**, y
el formulario no mostraba las preguntas de cifrado ni de borrado. Se superó porque el mismo
texto ya recomendaba la opción 2 para no arriesgar un rechazo (hallazgo A5 de la auditoría
del 2026-11-07).

## Antes de subir a Play

- El `.aab` está firmado con la clave de subida correcta (SHA-256 `A9:32:D2:18:…:A8:2C`, el
  mismo de las versiones anteriores).
- Versión 1.3.0 (build 9). Play ya tiene 1.2.0 (build 7) en prueba interna.
- Capturas nuevas (datos inventados) en `docs/screenshots/play/` (sin marco) y `docs/screenshots/` (con marco). Las versiones en inglés llevan el sufijo `.en.png` en las mismas carpetas; el gráfico destacado en inglés es `grafico-destacado.en.png`.
