import 'dart:io';

import 'package:bridgedesk/core/identity/device_identity.dart';
import 'package:bridgedesk/features/devices/device_model.dart';
import 'package:bridgedesk/features/pairing/pairing_service.dart';
import 'package:bridgedesk/features/pairing/pairing_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Full M1 handshake over TLS on loopback: host generates a PIN, the
/// client pairs with it, both sides store the pairing, a wrong PIN is
/// rejected with an attempt limit, and a changed certificate is refused
/// on reconnect. Runs on this Linux VM against 127.0.0.1 — no Mac or
/// Windows machine needed for the protocol itself.
void main() {
  group('pairing handshake (TLS loopback)', () {
    late Directory hostDir;
    late Directory clientDir;
    late DeviceIdentity hostIdentity;
    late DeviceIdentity clientIdentity;
    late PairingStore hostStore;
    late PairingStore clientStore;
    final List<PairingHostSession> sessions = <PairingHostSession>[];

    setUp(() async {
      hostDir = await Directory.systemTemp.createTemp('bridgedesk_h_');
      clientDir = await Directory.systemTemp.createTemp('bridgedesk_c_');
      hostIdentity = await DeviceIdentity.loadOrCreate(baseDir: hostDir);
      clientIdentity =
          await DeviceIdentity.loadOrCreate(baseDir: clientDir);
      hostStore = await PairingStore.load(baseDir: hostDir);
      clientStore = await PairingStore.load(baseDir: clientDir);
    });

    tearDown(() async {
      for (final PairingHostSession s in sessions) {
        await s.stop();
      }
      sessions.clear();
      if (await hostDir.exists()) await hostDir.delete(recursive: true);
      if (await clientDir.exists()) await clientDir.delete(recursive: true);
    });

    Future<PairingHostSession> startHost() async {
      final PairingHostSession session = await PairingHostSession.start(
        identity: hostIdentity,
        store: hostStore,
        port: 0, // ephemeral loopback port
      );
      sessions.add(session);
      return session;
    }

    PeerDevice peerFor(PairingHostSession session) => PeerDevice(
          deviceId: hostIdentity.deviceId,
          name: hostIdentity.deviceName,
          os: hostIdentity.os,
          ipAddress: '127.0.0.1',
          port: session.port,
        );

    String wrongPinFor(String pin) => pin == '123456' ? '654321' : '123456';

    test('correct PIN pairs and both sides remember it', () async {
      final PairingHostSession host = await startHost();
      final PairedDevice paired = await PairingClient.pair(
        peer: peerFor(host),
        pin: host.pin,
        identity: clientIdentity,
        store: clientStore,
      );
      expect(paired.deviceId, hostIdentity.deviceId);
      expect(paired.fingerprint, hostIdentity.fingerprint);
      expect(
        clientStore.findById(hostIdentity.deviceId)?.fingerprint,
        hostIdentity.fingerprint,
      );
      expect(
        hostStore.findById(clientIdentity.deviceId)?.fingerprint,
        clientIdentity.fingerprint,
      );
    });

    test('wrong PIN is rejected, 3 strikes lock the session out',
        () async {
      final PairingHostSession host = await startHost();
      final String wrong = wrongPinFor(host.pin);
      final PeerDevice peer = peerFor(host);

      PairingException e = await _expectPairingError(
        () => PairingClient.pair(
          peer: peer,
          pin: wrong,
          identity: clientIdentity,
          store: clientStore,
        ),
      );
      expect(e.failure, PairingFailure.wrongPin);
      expect(e.attemptsLeft, 2);

      e = await _expectPairingError(
        () => PairingClient.pair(
          peer: peer,
          pin: wrong,
          identity: clientIdentity,
          store: clientStore,
        ),
      );
      expect(e.failure, PairingFailure.wrongPin);
      expect(e.attemptsLeft, 1);

      e = await _expectPairingError(
        () => PairingClient.pair(
          peer: peer,
          pin: wrong,
          identity: clientIdentity,
          store: clientStore,
        ),
      );
      expect(e.failure, PairingFailure.tooManyAttempts);

      // Locked out: even the right PIN no longer works in this session.
      e = await _expectPairingError(
        () => PairingClient.pair(
          peer: peer,
          pin: host.pin,
          identity: clientIdentity,
          store: clientStore,
        ),
      );
      expect(e.failure, PairingFailure.tooManyAttempts);
      expect(clientStore.isEmpty, isTrue);
    });

    test('changed certificate is refused on reconnect', () async {
      // First pairing succeeds and pins the host fingerprint.
      final PairingHostSession host = await startHost();
      await PairingClient.pair(
        peer: peerFor(host),
        pin: host.pin,
        identity: clientIdentity,
        store: clientStore,
      );
      await host.stop();

      // Same device id, brand-new certificate (e.g. reinstall).
      final DeviceIdentity rotated =
          DeviceIdentity.createNew(deviceId: hostIdentity.deviceId);
      final PairingHostSession host2 = await PairingHostSession.start(
        identity: rotated,
        store: hostStore,
        port: 0,
      );
      sessions.add(host2);
      final PairingException e = await _expectPairingError(
        () => PairingClient.pair(
          peer: peerFor(host2),
          pin: host2.pin,
          identity: clientIdentity,
          store: clientStore,
        ),
      );
      expect(e.failure, PairingFailure.fingerprintMismatch);
    });

    test('connectPinned opens a channel to a paired device', () async {
      final PairingHostSession host = await startHost();
      await PairingClient.pair(
        peer: peerFor(host),
        pin: host.pin,
        identity: clientIdentity,
        store: clientStore,
      );
      final SecureSocket socket = await connectPinned(
        host: '127.0.0.1',
        port: host.port,
        expectedFingerprint: hostIdentity.fingerprint,
      );
      await socket.close();
      // ...and refuses a wrong fingerprint.
      await expectLater(
        connectPinned(
          host: '127.0.0.1',
          port: host.port,
          expectedFingerprint: '00' * 32,
        ),
        throwsA(
          isA<PairingException>().having(
            (PairingException e) => e.failure,
            'failure',
            PairingFailure.fingerprintMismatch,
          ),
        ),
      );
    });
  });
}

Future<PairingException> _expectPairingError(
  Future<PairedDevice> Function() run,
) async {
  try {
    await run();
  } on PairingException catch (e) {
    return e;
  }
  fail('Expected a PairingException');
}
