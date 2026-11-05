import '../../core/constants.dart';

/// A peer device found on the local network (or entered manually).
///
/// [deviceId] is the peer's stable BridgeDesk id from its mDNS TXT
/// record. Manual peers (no mDNS) get a synthetic id of the form
/// `manual:<ip>:<port>`. [fingerprint] is the peer's TLS certificate
/// fingerprint when known from mDNS; it is only a hint — the real
/// pinning check happens against the certificate presented on connect.
class PeerDevice {
  const PeerDevice({
    required this.deviceId,
    required this.name,
    required this.os,
    required this.ipAddress,
    this.port = bridgeDeskPort,
    this.fingerprint,
    this.isPaired = false,
    this.isManual = false,
  });

  /// A peer entered by hand (IP + port) when mDNS finds nothing.
  factory PeerDevice.manual(String ipAddress, int port) {
    return PeerDevice(
      deviceId: 'manual:$ipAddress:$port',
      name: ipAddress,
      os: 'Unknown',
      ipAddress: ipAddress,
      port: port,
      isManual: true,
    );
  }

  final String deviceId;
  final String name;
  final String os; // e.g. 'macOS', 'Windows', 'Linux', 'Unknown'
  final String ipAddress;
  final int port;
  final String? fingerprint;
  final bool isPaired;
  final bool isManual;

  PeerDevice copyWith({bool? isPaired, String? ipAddress, int? port}) {
    return PeerDevice(
      deviceId: deviceId,
      name: name,
      os: os,
      ipAddress: ipAddress ?? this.ipAddress,
      port: port ?? this.port,
      fingerprint: fingerprint,
      isPaired: isPaired ?? this.isPaired,
      isManual: isManual,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PeerDevice && other.deviceId == deviceId;

  @override
  int get hashCode => deviceId.hashCode;
}
