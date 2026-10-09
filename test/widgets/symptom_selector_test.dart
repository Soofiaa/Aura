import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aura/widgets/symptom_selector.dart';

/// Contenedor que hace de formulario: guarda la lista que entrega el
/// selector y se puede reconstruir por motivos ajenos (otro campo).
class _Host extends StatefulWidget {
  final List<String> inicial;

  const _Host({required this.inicial});

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late List<String> seleccion = widget.inicial;
  final List<List<String>> recibidas = [];
  int reconstrucciones = 0;

  /// Simula que llegan los datos del dia despues de construir.
  void cargar(List<String> datos) => setState(() => seleccion = datos);

  /// Reconstruccion sin cambiar los sintomas (p.ej. cambia el flujo).
  void reconstruir() => setState(() => reconstrucciones++);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SymptomSelector(
          selectedSymptoms: seleccion,
          onSelectionChanged: (nueva) {
            recibidas.add(nueva);
            setState(() => seleccion = nueva);
          },
        ),
      ),
    );
  }
}

bool _marcado(WidgetTester tester, String label) {
  final chip = find.ancestor(
    of: find.text(label),
    matching: find.byType(GestureDetector),
  );
  final icono = tester.widget<Icon>(
    find.descendant(of: chip.first, matching: find.byType(Icon)),
  );
  return icono.icon == Icons.check_circle;
}

void main() {
  testWidgets('muestra marcados los sintomas que recibe al construirse',
      (tester) async {
    await tester.pumpWidget(const _Host(inicial: ['Acné', 'Hinchazón']));

    expect(_marcado(tester, 'Acné'), isTrue);
    expect(_marcado(tester, 'Hinchazón'), isTrue);
    expect(_marcado(tester, 'Cansancio'), isFalse);
  });

  testWidgets(
      'si los sintomas llegan despues de construirse, se ven marcados',
      (tester) async {
    await tester.pumpWidget(const _Host(inicial: []));
    expect(_marcado(tester, 'Cansancio'), isFalse);

    final host = tester.state<_HostState>(find.byType(_Host));
    host.cargar(['Cansancio', 'Dolor de cabeza']);
    await tester.pump();

    expect(_marcado(tester, 'Cansancio'), isTrue);
    expect(_marcado(tester, 'Dolor de cabeza'), isTrue);
    expect(_marcado(tester, 'Antojos'), isFalse);

    // Y si cambian a otro dia (otra lista), se reemplazan, no se suman.
    host.cargar(['Antojos']);
    await tester.pump();
    expect(_marcado(tester, 'Antojos'), isTrue);
    expect(_marcado(tester, 'Cansancio'), isFalse);
    expect(_marcado(tester, 'Dolor de cabeza'), isFalse);
  });

  testWidgets(
      'marcar y desmarcar a mano funciona y no se pierde al reconstruir',
      (tester) async {
    // Lista constante: el selector no debe modificar la que recibe.
    await tester.pumpWidget(const _Host(inicial: ['Cansancio']));
    final host = tester.state<_HostState>(find.byType(_Host));

    await tester.tap(find.text('Antojos'));
    await tester.pump();
    expect(_marcado(tester, 'Antojos'), isTrue);
    expect(host.recibidas.last, ['Cansancio', 'Antojos']);

    await tester.tap(find.text('Cansancio'));
    await tester.pump();
    expect(_marcado(tester, 'Cansancio'), isFalse);
    expect(host.recibidas.last, ['Antojos']);

    host.reconstruir();
    await tester.pump();
    expect(_marcado(tester, 'Antojos'), isTrue);
    expect(_marcado(tester, 'Cansancio'), isFalse);

    // Cada cambio entrega una lista nueva, no la misma modificada.
    expect(identical(host.recibidas[0], host.recibidas[1]), isFalse);
    expect(host.recibidas[0], ['Cansancio', 'Antojos']);
  });
}
