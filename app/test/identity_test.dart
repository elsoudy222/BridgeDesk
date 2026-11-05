import 'dart:io';

import 'package:bridgedesk/core/identity/device_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loadOrCreate is stable across restarts', () async {
    final Directory tempDir =
        await Directory.systemTemp.createTemp('bridgedesk_id_');
    try {
      final DeviceIdentity first =
          await DeviceIdentity.loadOrCreate(baseDir: tempDir);
      final DeviceIdentity second =
          await DeviceIdentity.loadOrCreate(baseDir: tempDir);
      expect(second.deviceId, first.deviceId);
      expect(second.certificatePem, first.certificatePem);
      expect(second.privateKeyPem, first.privateKeyPem);
      expect(second.fingerprint, first.fingerprint);
    } finally {
      await tempDir.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('fingerprint is a 64-char lowercase hex SHA-256', () async {
    final Directory tempDir =
        await Directory.systemTemp.createTemp('bridgedesk_id_fp_');
    try {
      final DeviceIdentity identity =
          await DeviceIdentity.loadOrCreate(baseDir: tempDir);
      expect(identity.fingerprint.length, 64);
      expect(
        RegExp(r'^[0-9a-f]{64}$').hasMatch(identity.fingerprint),
        isTrue,
      );
      expect(
        DeviceIdentity.fingerprintOfCertPem(identity.certificatePem),
        identity.fingerprint,
      );
    } finally {
      await tempDir.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('two installs get different identities', () async {
    final Directory dirA =
        await Directory.systemTemp.createTemp('bridgedesk_id_a_');
    final Directory dirB =
        await Directory.systemTemp.createTemp('bridgedesk_id_b_');
    try {
      final DeviceIdentity a =
          await DeviceIdentity.loadOrCreate(baseDir: dirA);
      final DeviceIdentity b =
          await DeviceIdentity.loadOrCreate(baseDir: dirB);
      expect(a.deviceId, isNot(b.deviceId));
      expect(a.fingerprint, isNot(b.fingerprint));
    } finally {
      await dirA.delete(recursive: true);
      await dirB.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('createNew gives a fresh identity without persisting', () {
    final DeviceIdentity a =
        DeviceIdentity.createNew(deviceId: 'same-id');
    final DeviceIdentity b =
        DeviceIdentity.createNew(deviceId: 'same-id');
    // Same id, different keys: fingerprints must differ.
    expect(a.fingerprint, isNot(b.fingerprint));
  }, timeout: const Timeout(Duration(minutes: 2)));
}
