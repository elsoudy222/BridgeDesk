import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/storage/app_storage.dart';
import '../pairing/pairing_store.dart';

/// Which screen edge the mouse crosses to move to the other computer.
enum ScreenEdge { left, right }

/// Settings screen: edge, clipboard sharing, paired devices + unpair.
///
/// M1: the paired-devices list is real (loaded from [PairingStore])
/// and unpairing actually forgets the pairing — including the pinned
/// certificate fingerprint, so a later connection to that device needs
/// a fresh PIN pairing. Edge/clipboard settings are still local state;
/// they are applied by the M2/M3 lanes.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  ScreenEdge _edge = ScreenEdge.right;
  bool _clipboardSharing = true;

  PairingStore? _store;
  List<PairedDevice> _paired = const <PairedDevice>[];
  bool _loadingPaired = true;

  @override
  void initState() {
    super.initState();
    _loadPaired();
  }

  Future<void> _loadPaired() async {
    try {
      final Directory baseDir = await AppStorage.baseDir();
      final PairingStore store = await PairingStore.load(baseDir: baseDir);
      if (!mounted) return;
      setState(() {
        _store = store;
        _paired = store.paired;
        _loadingPaired = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingPaired = false);
    }
  }

  Future<void> _unpair(PairedDevice device) async {
    await _store?.remove(device.deviceId);
    if (!mounted) return;
    setState(() => _paired = _store?.paired ?? const <PairedDevice>[]);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Unpaired ${device.name}.')),
    );
  }

  Future<void> _unpairAll() async {
    await _store?.removeAll();
    if (!mounted) return;
    setState(() => _paired = const <PairedDevice>[]);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('All devices unpaired.')),
    );
  }

  String _shortFingerprint(String fingerprint) {
    if (fingerprint.length <= 16) return fingerprint;
    return '${fingerprint.substring(0, 8)}…${fingerprint.substring(fingerprint.length - 8)}';
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(
          'Mouse & keyboard',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        SegmentedButton<ScreenEdge>(
          segments: const <ButtonSegment<ScreenEdge>>[
            ButtonSegment<ScreenEdge>(
              value: ScreenEdge.left,
              label: Text('Left edge'),
              icon: Icon(Icons.arrow_back),
            ),
            ButtonSegment<ScreenEdge>(
              value: ScreenEdge.right,
              label: Text('Right edge'),
              icon: Icon(Icons.arrow_forward),
            ),
          ],
          selected: <ScreenEdge>{_edge},
          onSelectionChanged: (Set<ScreenEdge> value) {
            setState(() => _edge = value.first);
          },
        ),
        const SizedBox(height: 8),
        Text(
          'Move the mouse off the ${_edge.name} edge to switch '
          'to the other computer. (Applied in M2.)',
        ),
        const Divider(height: 32),
        SwitchListTile(
          title: const Text('Share clipboard (text)'),
          subtitle: const Text(
            'Copy on one computer, paste on the other. '
            'Text only in v1; sync lands in M3.',
          ),
          value: _clipboardSharing,
          onChanged: (bool value) {
            setState(() => _clipboardSharing = value);
          },
        ),
        const Divider(height: 32),
        Text(
          'Paired devices',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        if (_loadingPaired)
          const Center(child: CircularProgressIndicator())
        else if (_paired.isEmpty)
          const Text('No devices paired yet.')
        else
          ..._paired.map(
            (PairedDevice device) => ListTile(
              leading: Icon(
                device.os == 'macOS'
                    ? Icons.laptop_mac
                    : device.os == 'Windows'
                        ? Icons.laptop_windows
                        : Icons.laptop,
              ),
              title: Text(device.name),
              subtitle: Text(
                '${device.os} · ${device.ipAddress}:${device.port}\n'
                'Cert: ${_shortFingerprint(device.fingerprint)}',
              ),
              trailing: IconButton(
                icon: const Icon(Icons.link_off),
                tooltip: 'Unpair ${device.name}',
                onPressed: () => _unpair(device),
              ),
            ),
          ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _paired.isEmpty ? null : _unpairAll,
          icon: const Icon(Icons.link_off),
          label: const Text('Unpair all devices'),
        ),
      ],
    );
  }
}
