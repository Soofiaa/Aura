import 'package:flutter/material.dart';
import 'backup_create_flow.dart';
import 'calendar_screen.dart';
import 'home_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import '../utils/aura_localizations.dart';
import '../utils/colors.dart';

/// Shell de navegacion: NavigationBar de Material 3 con 4 destinos fijos.
/// Cada pantalla conserva su propio Scaffold/AppBar; esto solo agrega la
/// barra inferior y mantiene el estado de cada pestana con IndexedStack.
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;

  // Una sola operacion de respaldo a la vez entre Ajustes e Inicio (la
  // tarjeta del recordatorio abre el mismo flujo que "Crear respaldo").
  // No se libera: un flujo en curso lo vuelve a false al terminar.
  final ValueNotifier<bool> _backupBusy = ValueNotifier<bool>(false);

  static const _screens = [
    HomeScreen(),
    CalendarScreen(),
    StatsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return BackupBusyScope(
      busy: _backupBusy,
      child: _scaffold(),
    );
  }

  Widget _scaffold() {
    return Scaffold(
      // Edge-to-edge: en horizontal la camara y las barras quedan a los
      // lados; arriba y abajo ya los cubren cada AppBar y la NavigationBar.
      body: SafeArea(
        top: false,
        bottom: false,
        child: IndexedStack(index: _currentIndex, children: _screens),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        // Pildora de la pestaña seleccionada: mismo relleno del tema y un
        // borde de 3,32:1 sobre la barra (antes 1,12:1 sin borde).
        indicatorShape: const StadiumBorder(
          side: BorderSide(
            color: AppColors.navIndicatorBorder,
            width: AppColors.thinBorderWidth,
          ),
        ),
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: tr('Inicio', 'Home'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.calendar_month_outlined),
            selectedIcon: const Icon(Icons.calendar_month),
            label: tr('Calendario', 'Calendar'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.show_chart_outlined),
            selectedIcon: const Icon(Icons.show_chart),
            label: tr('Estadísticas', 'Stats'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: tr('Ajustes', 'Settings'),
          ),
        ],
      ),
    );
  }
}
