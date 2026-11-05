import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:crypto/crypto.dart';

/// A device's identity for pairing and TLS.
///
/// Every BridgeDesk install generates, once, a stable device id plus a
/// 2048-bit RSA key pair and a self-signed certificate (valid 10 years).
/// The private key never leaves the device. The certificate fingerprint
/// (SHA-256 of the DER certificate, hex) is what peers pin at pairing
/// time; a changed fingerprint on reconnect is rejected, never silently
/// accepted.
///
/// The certificate is *not* trusted by any CA — that is the point.
/// Trust is established out-of-band by the 6-digit PIN (trust on first
/// use, authenticated by the PIN) and then by fingerprint pinning.
class DeviceIdentity {
  const DeviceIdentity({
    required this.deviceId,
    required this.deviceName,
    required this.os,
    required this.certificatePem,
    required this.privateKeyPem,
  });

  /// Stable id, generated once and stored in `identity/device_id.txt`.
  final String deviceId;

  /// Human name shown to peers (the OS hostname).
  final String deviceName;

  /// Display OS: 'macOS', 'Windows' or 'Linux'.
  final String os;

  /// PEM self-signed certificate.
  final String certificatePem;

  /// PEM PKCS#8 private key. Never sent anywhere.
  final String privateKeyPem;

  /// SHA-256 fingerprint of the DER certificate, lowercase hex.
  String get fingerprint => fingerprintOfCertPem(certificatePem);

  /// Fingerprint of any PEM certificate.
  static String fingerprintOfCertPem(String certPem) {
    return sha256.convert(_derFromPem(certPem)).toString();
  }

  static Uint8List _derFromPem(String pem) {
    // basic_utils emits CRLF line endings; strip them before decoding.
    final String body = pem
        .split(RegExp(r'\r?\n'))
        .map((String line) => line.trim())
        .where((String line) =>
            line.isNotEmpty && !line.startsWith('-----'))
        .join();
    return base64Decode(body);
  }

  /// Loads the stored identity, or generates and stores a fresh one.
  /// [baseDir] is the `bridgedesk` directory (see [AppStorage]).
  static Future<DeviceIdentity> loadOrCreate({
    required Directory baseDir,
  }) async {
    final Directory dir = Directory(
      '${baseDir.path}${Platform.pathSeparator}identity',
    );
    await dir.create(recursive: true);
    final File idFile = File('${dir.path}${Platform.pathSeparator}device_id.txt');
    final File certFile =
        File('${dir.path}${Platform.pathSeparator}cert.pem');
    final File keyFile =
        File('${dir.path}${Platform.pathSeparator}key.pem');

    if (await idFile.exists() &&
        await certFile.exists() &&
        await keyFile.exists()) {
      return DeviceIdentity(
        deviceId: (await idFile.readAsString()).trim(),
        deviceName: deviceNameForPlatform(),
        os: osForPlatform(),
        certificatePem: await certFile.readAsString(),
        privateKeyPem: await keyFile.readAsString(),
      );
    }

    final DeviceIdentity fresh = createNew(deviceId: _newDeviceId());
    await idFile.writeAsString(fresh.deviceId);
    await certFile.writeAsString(fresh.certificatePem);
    await keyFile.writeAsString(fresh.privateKeyPem);
    return fresh;
  }

  /// Generates a fresh identity in memory (not persisted). Used by
  /// [loadOrCreate] and by tests that need a second, distinct identity.
  static DeviceIdentity createNew({required String deviceId}) {
    final AsymmetricKeyPair<PublicKey, PrivateKey> keyPair =
        CryptoUtils.generateRSAKeyPair(keySize: 2048);
    final RSAPublicKey publicKey = keyPair.publicKey as RSAPublicKey;
    final RSAPrivateKey privateKey = keyPair.privateKey as RSAPrivateKey;
    final String csr = X509Utils.generateRsaCsrPem(
      <String, String>{'CN': 'BridgeDesk $deviceId'},
      privateKey,
      publicKey,
    );
    // NOTE: no keyUsage / extKeyUsage extensions. basic_utils encodes
    // those extensions in a form BoringSSL (Dart's TLS stack) rejects
    // with CANNOT_PARSE_LEAF_CERT, while OpenSSL accepts it. The cert
    // is pinned by fingerprint, never chain-validated, so extensions
    // add nothing here.
    final String certPem = X509Utils.generateSelfSignedCertificate(
      privateKey,
      csr,
      3650, // 10 years
    );
    return DeviceIdentity(
      deviceId: deviceId,
      deviceName: deviceNameForPlatform(),
      os: osForPlatform(),
      certificatePem: certPem,
      privateKeyPem: CryptoUtils.encodeRSAPrivateKeyToPem(privateKey),
    );
  }

  static String _newDeviceId() {
    final Random random = Random.secure();
    final List<int> bytes =
        List<int>.generate(16, (_) => random.nextInt(256));
    return bytes
        .map((int b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// Human device name for this platform.
  static String deviceNameForPlatform() {
    try {
      return Platform.localHostname;
    } catch (_) {
      return 'BridgeDesk device';
    }
  }

  /// Display OS for this platform.
  static String osForPlatform() {
    switch (Platform.operatingSystem) {
      case 'macos':
        return 'macOS';
      case 'windows':
        return 'Windows';
      case 'linux':
        return 'Linux';
      default:
        return Platform.operatingSystem;
    }
  }
}
