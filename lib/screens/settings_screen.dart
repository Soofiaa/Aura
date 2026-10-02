import 'package:flutter/material.dart';
import '../data/repositories/cycle_repository.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notificaciones = true;

  // dark_mode todavia no tiene columna en app_settings (fase 2, punto 4):
  // queda como estado local de la pantalla, no persistido, igual que
  // antes no afectaba el tema de la app.
  bool _modoOscuro = false;

  @override
  void initState() {
    super.initState();
    _cargarPreferencias();
  }

  Future<void> _cargarPreferencias() async {
    final notificaciones = await cycleRepository.getNotificationsEnabled();
    if (!mounted) return;
    setState(() => _notificaciones = notificaciones);
  }

  Future<void> _guardarPreferencias() async {
    await cycleRepository.setNotificationsEnabled(_notificaciones);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Preferencias guardadas 🩵")),
    );
  }

  Future<void> _confirmarYBorrarDatos() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("¿Borrar todos los datos?"),
        content: const Text(
          "Se eliminaran todos los dias registrados, sintomas y ajustes. "
          "Esta accion no se puede deshacer.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancelar"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              "Borrar todo",
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmado != true) return;

    await cycleRepository.deleteAllData();

    if (!mounted) return;
    setState(() => _notificaciones = true);
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
            onPressed: _confirmarYBorrarDatos,
            icon: const Icon(Icons.delete_forever),
            label: const Text("Borrar todos los datos"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.pinkAccent.withValues(alpha: 0.8),
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
