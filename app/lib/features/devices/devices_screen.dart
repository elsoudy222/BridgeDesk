import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants.dart';
import '../../core/identity/device_identity.dart';
import '../../core/storage/app_storage.dart';
import '../pairing/pairing_store.dart';
import 'device_model.dart';
import 'discovery_service.dart';

/// Devices screen: discovered + paired peers on the same Wi-Fi.
///
/// M1: real mDNS discovery (plus a manual-IP fallback). Tapping Pair
/// hands the peer to the Pairing tab. Services load lazily on first
/// search so the app still boots where mDNS / the app-support folder
/// is unavailable (e.g. widget tests) — failures just yield an empty
/// list and an explanatory note, never a crash.
class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key, required this.onPairRequested});

  final void Function(PeerDevice peer) onPairRequested;

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController =
      TextEditingController(text: '$bridgeDeskPort');

  DiscoveryService? _discovery;
  PairingStore? _store;
  Future<void>? _initFuture;
  bool _searching = false;
  String? _note;
  List<PeerDevice> _devices = const <PeerDevice>[];

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _discovery?.stop();
    _discovery?.dispose();
    super.dispose();
  }

  Future<void> _ensureServices() {
    return _initFuture ??= () async {
      final Directory baseDir = await AppStorage.baseDir();
      final DeviceIdentity identity =
          await DeviceIdentity.loadOrCreate(baseDir: baseDir);
      _store = await PairingStore.load(baseDir: baseDir);
      _discovery = DiscoveryService(identity: identity);
      await _discovery!.startAdvertising();
    }();
  }

  Future<void> _search() async {
    if (_searching) return;
    setState(() {
      _searching = true;
      _note = null;
    });
    try {
      await _ensureServices();
      final List<PeerDevice> found = await _discovery!.discover();
      if (!mounted) return;
      setState(() {
        _devices = _withPairedFlags(found);
        _searching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _note = 'Discovery is unavailable here ($e). '
            'You can still add the other computer by IP below.';
      });
    }
  }

  List<PeerDevice> _withPairedFlags(List<PeerDevice> peers) {
    final PairingStore? store = _store;
    if (store == null) return peers;
    return peers
        .map(
          (PeerDevice peer) => peer.copyWith(
            isPaired: store.findById(peer.deviceId) != null,
          ),
        )
        .toList();
  }

  void _addManual() {
    final String ip = _ipController.text.trim();
    final int port =
        int.tryParse(_portController.text.trim()) ?? bridgeDeskPort;
    final PeerDevice? peer = _discovery?.addManualPeer(ip, port);
    if (peer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid IPv4 address and port.'),
        ),
      );
      return;
    }
    setState(() {
      _devices = _withPairedFlags(_discovery!.currentPeers);
      _ipController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Scrollable (not Expanded) layout: the empty state and the manual-IP
    // row must fit small windows without overflowing the column.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _searching
                      ? 'Searching on LAN…'
                      : _devices.isEmpty
                          ? 'No devices found yet'
                          : '${_devices.length} device(s) found',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FilledButton.icon(
                onPressed: _searching ? null : _search,
                icon: const Icon(Icons.refresh),
                label: const Text('Search'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Both devices must be on the same Wi-Fi. '
            'BridgeDesk advertises itself on the LAN; '
            'if nothing appears, add the other computer by IP below.',
          ),
          if (_note != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(_note!, style: TextStyle(color: Colors.orange.shade800)),
          ],
          const SizedBox(height: 16),
          if (_searching)
            const SizedBox(
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_devices.isEmpty)
            const SizedBox(
              height: 160,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.devices_other, size: 48),
                    SizedBox(height: 12),
                    Text(
                      'No nearby devices.\n'
                      'Start BridgeDesk on your other computer\n'
                      'and make sure both are on the same Wi-Fi.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            SizedBox(
              height: 320,
              child: ListView.builder(
                itemCount: _devices.length,
                itemBuilder: (BuildContext context, int index) {
                  final PeerDevice device = _devices[index];
                  return ListTile(
                    leading: Icon(
                      device.os == 'macOS'
                          ? Icons.laptop_mac
                          : device.os == 'Windows'
                              ? Icons.laptop_windows
                              : Icons.laptop,
                    ),
                    title: Text(device.name),
                    subtitle: Text(
                      '${device.os} · ${device.ipAddress}:${device.port}'
                      '${device.isManual ? ' · manual' : ''}',
                    ),
                    trailing: device.isPaired
                        ? const Chip(label: Text('Paired'))
                        : FilledButton(
                            onPressed: () => widget.onPairRequested(device),
                            child: const Text('Pair'),
                          ),
                  );
                },
              ),
            ),
          const SizedBox(height: 16),
          const Text(
            'Add by IP (when discovery finds nothing):',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _ipController,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(
                      RegExp(r'[0-9.]'),
                    ),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'IP address',
                    hintText: 'e.g. 192.168.1.20',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _portController,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Port',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _addManual,
                child: const Text('Add'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {
              // TODO (M3): open a file picker and send the chosen file
              // to the paired device over the TLS channel.
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Send File comes in M3 — pair a device '
                      'first.'),
                ),
              );
            },
            icon: const Icon(Icons.send),
            label: const Text('Send File'),
          ),
        ],
      ),
    );
  }
}
