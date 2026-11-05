import 'dart:async';
import 'dart:io';

import 'package:bonsoir/bonsoir.dart';

import '../../core/constants.dart';
import '../../core/identity/device_identity.dart';
import 'device_model.dart';

/// LAN discovery over mDNS/Bonjour (`bonsoir`).
///
/// This device advertises itself as `_bridgedesk._tcp` with a TXT
/// record carrying its stable id, OS and certificate fingerprint, and
/// browses for the same service. Everything stays on the LAN: no cloud,
/// no account, no central server.
///
/// Platform notes:
/// * macOS needs the multicast entitlement + `NSBonjourServices` for
///   `_bridgedesk._tcp` (added to the Runner in M1); without them the
///   OS silently blocks mDNS.
/// * Windows shows a firewall prompt on first use; the app must be
///   allowed on private networks.
/// * In environments without an mDNS implementation (e.g. `flutter
///   test` on this Linux VM) every call fails closed: broadcast and
///   browse throw, are caught here, and discovery simply returns the
///   peers found so far (usually none) instead of crashing.
class DiscoveryService {
  DiscoveryService({
    required this.identity,
    this.port = bridgeDeskPort,
    this.scanDuration = const Duration(seconds: 3),
  });

  final DeviceIdentity identity;
  final int port;
  final Duration scanDuration;

  final Map<String, PeerDevice> _found = <String, PeerDevice>{};
  final List<PeerDevice> _manual = <PeerDevice>[];
  final StreamController<List<PeerDevice>> _peersController =
      StreamController<List<PeerDevice>>.broadcast();

  BonsoirBroadcast? _broadcast;
  bool _advertising = false;

  /// Live peer list: discovered peers plus manually added ones.
  Stream<List<PeerDevice>> get peers => _peersController.stream;

  /// All peers known right now.
  List<PeerDevice> get currentPeers => <PeerDevice>[
        ..._found.values,
        ..._manual,
      ];

  /// Starts advertising this device. Safe to call repeatedly; safe to
  /// call where mDNS is unavailable (logs nothing, just no-ops).
  Future<void> startAdvertising() async {
    if (_advertising) return;
    try {
      final BonsoirService service = BonsoirService(
        name: identity.deviceName,
        type: bridgeDeskServiceType,
        port: port,
        attributes: <String, String>{
          'id': identity.deviceId,
          'os': identity.os,
          // TXT records are short strings; the full 64-hex fingerprint
          // fits (64 chars, well under the 255-byte limit).
          'fp': identity.fingerprint,
        },
      );
      final BonsoirBroadcast broadcast = BonsoirBroadcast(service: service);
      await broadcast.initialize();
      await broadcast.start();
      _broadcast = broadcast;
      _advertising = true;
    } catch (_) {
      // No mDNS on this platform/environment: manual-IP fallback
      // is still available, so this is not fatal.
      _advertising = false;
    }
  }

  /// Scans the LAN for peers for [scanDuration] and returns them.
  /// Never throws: on any mDNS failure it returns what it found (which
  /// may be empty). Our own advertisement is ignored (same device id).
  Future<List<PeerDevice>> discover() async {
    try {
      final BonsoirDiscovery discovery =
          BonsoirDiscovery(type: bridgeDeskServiceType);
      await discovery.initialize();
      final StreamSubscription<BonsoirDiscoveryEvent>? subscription =
          discovery.eventStream?.listen((BonsoirDiscoveryEvent event) {
        if (event is BonsoirDiscoveryServiceFoundEvent) {
          event.service.resolve(discovery.serviceResolver);
        } else if (event is BonsoirDiscoveryServiceResolvedEvent ||
            event is BonsoirDiscoveryServiceUpdatedEvent) {
          final BonsoirService? service = event.service;
          if (service != null) _addResolved(service);
        } else if (event is BonsoirDiscoveryServiceLostEvent) {
          _found.remove(event.service.attributes['id']);
          _emit();
        }
      });
      await discovery.start();
      await Future<void>.delayed(scanDuration);
      await subscription?.cancel();
      await discovery.stop();
    } catch (_) {
      // mDNS unavailable: fall through with whatever was found.
    }
    return currentPeers;
  }

  /// Adds a peer entered by hand (IP + port). Returns the peer, or
  /// null when [ipAddress] is not a valid IP address.
  PeerDevice? addManualPeer(String ipAddress, int port) {
    final InternetAddress? parsed = InternetAddress.tryParse(ipAddress);
    if (parsed == null || port < 1 || port > 65535) return null;
    final PeerDevice peer = PeerDevice.manual(ipAddress, port);
    _manual.removeWhere((PeerDevice p) => p.deviceId == peer.deviceId);
    _manual.add(peer);
    _emit();
    return peer;
  }

  void _addResolved(BonsoirService service) {
    final String? id = service.attributes['id'];
    if (id == null || id.isEmpty || id == identity.deviceId) return;
    final String ip = service.hostAddresses.firstWhere(
      (String address) =>
          InternetAddress.tryParse(address)?.type ==
          InternetAddressType.IPv4,
      orElse: () => '',
    );
    if (ip.isEmpty) return;
    _found[id] = PeerDevice(
      deviceId: id,
      name: service.name,
      os: service.attributes['os'] ?? 'Unknown',
      ipAddress: ip,
      port: service.port,
      fingerprint: service.attributes['fp'],
    );
    _emit();
  }

  void _emit() {
    if (!_peersController.isClosed) {
      _peersController.add(currentPeers);
    }
  }

  /// Stops advertising. Discovery scans stop on their own after
  /// [scanDuration]; call this when the app closes.
  Future<void> stop() async {
    try {
      await _broadcast?.stop();
    } catch (_) {}
    _broadcast = null;
    _advertising = false;
  }

  void dispose() {
    _peersController.close();
  }
}
