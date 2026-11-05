import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants.dart';
import '../../core/identity/device_identity.dart';
import '../../core/storage/app_storage.dart';
import '../devices/device_model.dart';
import 'pairing_service.dart';
import 'pairing_store.dart';
import 'pin.dart';

/// Pairing screen: host a pairing (show our PIN) or pair with a peer
/// (enter the PIN shown on the other device).
///
/// Flow: on the host, tap "Show my PIN" — a fresh random PIN is
/// generated and the TLS server starts listening. On the client, pick
/// the peer (from the Devices tab, or type its IP + port here), enter
/// that PIN and tap "Verify PIN & Pair". On success both sides remember
/// the pairing, including each other's certificate fingerprint.
class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key, required this.pairingTarget});

  /// Peer selected on the Devices tab; null = none selected yet.
  final ValueNotifier<PeerDevice?> pairingTarget;

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController =
      TextEditingController(text: '$bridgeDeskPort');

  DeviceIdentity? _identity;
  PairingStore? _store;
  Future<void>? _initFuture;

  PairingHostSession? _hostSession;
  StreamSubscription<PairingHostEvent>? _hostEvents;
  String? _hostPin;
  bool _hostBusy = false;
  String? _hostStatus;

  bool _clientBusy = false;
  String? _clientStatus;
  PeerDevice? _target;

  @override
  void initState() {
    super.initState();
    _target = widget.pairingTarget.value;
    widget.pairingTarget.addListener(_onTargetChanged);
  }

  @override
  void dispose() {
    widget.pairingTarget.removeListener(_onTargetChanged);
    _pinController.dispose();
    _ipController.dispose();
    _portController.dispose();
    _hostEvents?.cancel();
    _hostSession?.stop();
    super.dispose();
  }

  void _onTargetChanged() {
    setState(() => _target = widget.pairingTarget.value);
  }

  Future<void> _ensureServices() {
    return _initFuture ??= () async {
      final Directory baseDir = await AppStorage.baseDir();
      _identity = await DeviceIdentity.loadOrCreate(baseDir: baseDir);
      _store = await PairingStore.load(baseDir: baseDir);
    }();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _startHosting() async {
    if (_hostBusy) return;
    setState(() {
      _hostBusy = true;
      _hostStatus = null;
    });
    try {
      await _ensureServices();
      await _hostSession?.stop();
      final PairingHostSession session = await PairingHostSession.start(
        identity: _identity!,
        store: _store!,
      );
      _hostEvents?.cancel();
      _hostEvents = session.events.listen((PairingHostEvent event) {
        if (!mounted) return;
        if (event.kind == PairingHostEventKind.paired) {
          setState(() {
            _hostStatus = 'Paired with ${event.peer?.name ?? 'a device'}.';
          });
          _showMessage('Paired with ${event.peer?.name ?? 'a device'}.');
        } else {
          setState(() {
            _hostStatus =
                'Too many wrong PINs. Stop and generate a fresh PIN.';
          });
        }
      });
      if (!mounted) return;
      setState(() {
        _hostSession = session;
        _hostPin = session.pin;
        _hostBusy = false;
        _hostStatus = 'Waiting for the other device to enter this PIN…';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _hostBusy = false);
      _showMessage('Could not start hosting: $e');
    }
  }

  Future<void> _stopHosting() async {
    await _hostEvents?.cancel();
    await _hostSession?.stop();
    if (!mounted) return;
    setState(() {
      _hostSession = null;
      _hostPin = null;
      _hostStatus = null;
    });
  }

  PeerDevice? _resolveTarget() {
    if (_target != null) return _target;
    final String ip = _ipController.text.trim();
    final int port =
        int.tryParse(_portController.text.trim()) ?? bridgeDeskPort;
    if (InternetAddress.tryParse(ip) == null) return null;
    return PeerDevice.manual(ip, port);
  }

  Future<void> _pair() async {
    if (_clientBusy) return;
    final String pin = _pinController.text.trim();
    if (!PinGenerator.isWellFormed(pin)) {
      _showMessage('Enter a 6-digit PIN.');
      return;
    }
    final PeerDevice? peer = _resolveTarget();
    if (peer == null) {
      _showMessage('Pick a device on the Devices tab, or enter its IP.');
      return;
    }
    setState(() {
      _clientBusy = true;
      _clientStatus = null;
    });
    try {
      await _ensureServices();
      final PairedDevice paired = await PairingClient.pair(
        peer: peer,
        pin: pin,
        identity: _identity!,
        store: _store!,
      );
      if (!mounted) return;
      setState(() {
        _clientBusy = false;
        _clientStatus = 'Paired with ${paired.name}.';
      });
      _pinController.clear();
      _showMessage('Paired with ${paired.name}.');
    } on PairingException catch (e) {
      if (!mounted) return;
      setState(() {
        _clientBusy = false;
        _clientStatus = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _clientBusy = false;
        _clientStatus = 'Pairing failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(
          'Host a pairing',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'Show a PIN on this device; the other device enters it. '
          'A fresh PIN is generated every time you start hosting, '
          'and it stops working after 3 wrong guesses.',
        ),
        const SizedBox(height: 16),
        if (_hostPin != null)
          Center(
            child: Text(
              _hostPin!,
              style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    letterSpacing: 8,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
            ),
          ),
        if (_hostStatus != null) ...<Widget>[
          const SizedBox(height: 8),
          Center(child: Text(_hostStatus!)),
        ],
        const SizedBox(height: 16),
        if (_hostSession == null)
          FilledButton(
            onPressed: _hostBusy ? null : _startHosting,
            child: Text(_hostBusy ? 'Starting…' : 'Show my PIN'),
          )
        else
          OutlinedButton(
            onPressed: _stopHosting,
            child: const Text('Stop hosting'),
          ),
        const Divider(height: 40),
        Text(
          'Pair with a device',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        if (_target != null)
          Text(
            'Selected: ${_target!.name} '
            '(${_target!.os} · ${_target!.ipAddress}:${_target!.port})',
          )
        else ...<Widget>[
          const Text('No device selected — enter its IP and port:'),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _ipController,
                  keyboardType: TextInputType.number,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
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
            ],
          ),
        ],
        const SizedBox(height: 16),
        const Text('Enter the PIN shown on the other device:'),
        const SizedBox(height: 8),
        TextField(
          controller: _pinController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          decoration: const InputDecoration(
            labelText: '6-digit PIN',
            border: OutlineInputBorder(),
            counterText: '',
          ),
          onSubmitted: (_) => _pair(),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _clientBusy ? null : _pair,
          child: Text(_clientBusy ? 'Pairing…' : 'Verify PIN & Pair'),
        ),
        if (_clientStatus != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(_clientStatus!),
        ],
        const SizedBox(height: 16),
        const Text(
          'Pairing runs over an encrypted (TLS) connection. '
          'The PIN is never sent in the clear, and each device pins '
          'the other\'s certificate — if it ever changes, the '
          'connection is refused. No account, no cloud.',
        ),
      ],
    );
  }
}
