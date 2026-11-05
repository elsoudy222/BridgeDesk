import 'package:flutter/material.dart';

import 'features/devices/device_model.dart';
import 'features/devices/devices_screen.dart';
import 'features/pairing/pairing_screen.dart';
import 'features/settings/settings_screen.dart';

/// BridgeDesk M1.
///
/// Clean-room MVP: one mouse/keyboard, shared clipboard and file send
/// between a Mac and a Windows PC on the same Wi-Fi. No account, no cloud.
///
/// M1 scope: real mDNS discovery, 6-digit PIN pairing and a TLS
/// channel (see MVP_PLAN.md). Mouse/keyboard sharing is M2, clipboard
/// sync and file transfer are M3.
void main() {
  runApp(const BridgeDeskApp());
}

class BridgeDeskApp extends StatelessWidget {
  const BridgeDeskApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BridgeDesk',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  /// The peer the user tapped "Pair" on, handed to the Pairing tab.
  /// Null means "no peer selected yet — use the manual fields".
  final ValueNotifier<PeerDevice?> pairingTarget =
      ValueNotifier<PeerDevice?>(null);

  @override
  void dispose() {
    pairingTarget.dispose();
    super.dispose();
  }

  void _pairWith(PeerDevice peer) {
    pairingTarget.value = peer;
    setState(() => _index = 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('BridgeDesk')),
      body: IndexedStack(
        index: _index,
        children: <Widget>[
          DevicesScreen(onPairRequested: _pairWith),
          PairingScreen(pairingTarget: pairingTarget),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (int value) {
          setState(() => _index = value);
        },
        destinations: const <NavigationDestination>[
          NavigationDestination(
            icon: Icon(Icons.devices),
            label: 'Devices',
          ),
          NavigationDestination(
            icon: Icon(Icons.key),
            label: 'Pairing',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
