import 'dart:convert';
import 'dart:io';

/// A device we have paired with.
///
/// The [fingerprint] is the peer's TLS certificate fingerprint, pinned
/// at pairing time. On reconnect the peer must present a certificate
/// with this fingerprint or the connection is rejected.
class PairedDevice {
  const PairedDevice({
    required this.deviceId,
    required this.name,
    required this.os,
    required this.ipAddress,
    required this.port,
    required this.fingerprint,
    required this.pairedAt,
  });

  factory PairedDevice.fromJson(Map<String, dynamic> json) {
    return PairedDevice(
      deviceId: json['deviceId'] as String,
      name: json['name'] as String,
      os: json['os'] as String,
      ipAddress: json['ipAddress'] as String,
      port: (json['port'] as num).toInt(),
      fingerprint: json['fingerprint'] as String,
      pairedAt: DateTime.parse(json['pairedAt'] as String),
    );
  }

  final String deviceId;
  final String name;
  final String os;
  final String ipAddress;
  final int port;
  final String fingerprint;
  final DateTime pairedAt;

  PairedDevice copyWith({String? ipAddress, int? port}) {
    return PairedDevice(
      deviceId: deviceId,
      name: name,
      os: os,
      ipAddress: ipAddress ?? this.ipAddress,
      port: port ?? this.port,
      fingerprint: fingerprint,
      pairedAt: pairedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'deviceId': deviceId,
      'name': name,
      'os': os,
      'ipAddress': ipAddress,
      'port': port,
      'fingerprint': fingerprint,
      'pairedAt': pairedAt.toIso8601String(),
    };
  }
}

/// Persistent store of paired devices (`pairings.json` under the app
/// base directory). Pairings survive restarts; unpairing removes them.
class PairingStore {
  PairingStore(this._file, [List<PairedDevice>? initial])
      : _paired = List<PairedDevice>.from(initial ?? const <PairedDevice>[]);

  /// Loads the store from [baseDir]/pairings.json (empty if missing).
  static Future<PairingStore> load({required Directory baseDir}) async {
    final File file = File(
      '${baseDir.path}${Platform.pathSeparator}pairings.json',
    );
    if (!await file.exists()) return PairingStore(file);
    try {
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return PairingStore(file);
      final List<PairedDevice> paired = decoded
          .whereType<Map<String, dynamic>>()
          .map(PairedDevice.fromJson)
          .toList();
      return PairingStore(file, paired);
    } catch (_) {
      // A corrupt file must not brick the app; start empty.
      return PairingStore(file);
    }
  }

  final File _file;
  final List<PairedDevice> _paired;

  List<PairedDevice> get paired => List<PairedDevice>.unmodifiable(_paired);

  PairedDevice? findById(String deviceId) {
    for (final PairedDevice device in _paired) {
      if (device.deviceId == deviceId) return device;
    }
    return null;
  }

  bool get isEmpty => _paired.isEmpty;

  /// Adds or replaces the pairing for [device.deviceId].
  Future<void> add(PairedDevice device) async {
    _paired.removeWhere((PairedDevice d) => d.deviceId == device.deviceId);
    _paired.add(device);
    await _save();
  }

  /// Removes the pairing for [deviceId]; no-op when unknown.
  Future<void> remove(String deviceId) async {
    _paired.removeWhere((PairedDevice d) => d.deviceId == deviceId);
    await _save();
  }

  /// Forgets every pairing (Settings "Unpair all").
  Future<void> removeAll() async {
    _paired.clear();
    await _save();
  }

  Future<void> _save() async {
    final String json = jsonEncode(
      _paired.map((PairedDevice d) => d.toJson()).toList(),
    );
    await _file.writeAsString(json);
  }
}
