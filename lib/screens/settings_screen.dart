import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../data/database/hive_boxes.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificaciones = true;
  bool _modoOscuro = false;

  @override
  void initState() {
    super.initState();
    final box = HiveBoxes.getDiasBox();
    _notificaciones = box.get('notificaciones', defaultValue: true);
    _modoOscuro = box.get('modoOscuro', defaultValue: false);
  }

  void _guardarPreferencias() {
    final box = HiveBoxes.diasMenstruacion;
    box.put('notificaciones', _notificaciones);
    box.put('modoOscuro', _modoOscuro);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Preferencias guardadas 🩵")),
    );
  }

  void _borrarDatos() async {
    final box = HiveBoxes.diasMenstruacion;
    await box.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Datos borrados correctamente 💧")),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Configuración"),
        backgroundColor: const Color(0xFFA8D8EA),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            "Preferencias generales",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),

          // 🔔 Notificaciones
          SwitchListTile(
            title: const Text("Notificaciones locales"),
            subtitle: const Text("Recordatorios de menstruación o píldora"),
            activeColor: const Color(0xFFA8D8EA),
            value: _notificaciones,
            onChanged: (val) {
              setState(() => _notificaciones = val);
            },
          ),

          // 🌙 Tema
          SwitchListTile(
            title: const Text("Modo oscuro"),
            subtitle: const Text("Reduce brillo y usa fondo oscuro"),
            activeColor: const Color(0xFFA8D8EA),
            value: _modoOscuro,
            onChanged: (val) {
              setState(() => _modoOscuro = val);
            },
          ),

          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: _guardarPreferencias,
            icon: const Icon(Icons.save),
            label: const Text("Guardar preferencias"),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFA8D8EA),
              foregroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),

          const SizedBox(height: 40),
          const Divider(),
          const SizedBox(height: 20),

          const Text(
            "Gestión de datos",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: _borrarDatos,
            icon: const Icon(Icons.delete_forever),
            label: const Text("Borrar todos los datos"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.pinkAccent.withOpacity(0.8),
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),

          const SizedBox(height: 20),
          const Text(
            "Versión 1.0.0 • Aura 🌸",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
