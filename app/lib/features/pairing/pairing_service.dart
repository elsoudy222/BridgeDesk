import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../core/constants.dart';
import '../../core/identity/device_identity.dart';
import '../../core/transport/secure_channel.dart';
import '../devices/device_model.dart';
import 'pairing_store.dart';
import 'pin.dart';

/// Why a pairing attempt failed. Surfaced to the UI verbatim so the
/// user can tell a wrong PIN from a changed certificate.
enum PairingFailure {
  wrongPin,
  tooManyAttempts,
  fingerprintMismatch,
  timeout,
  connectionFailed,
}

class PairingException implements Exception {
  PairingException(this.failure, this.message, {this.attemptsLeft});

  final PairingFailure failure;
  final String message;
  final int? attemptsLeft;

  @override
  String toString() => 'PairingException($failure): $message';
}

/// Handshake wire protocol (JSON control messages over the TLS channel).
///
/// Client -> host: `pair_request`
///   {type, deviceId, deviceName, os, port, pin, fingerprint}
/// Host -> client: `pair_ok`
///   {type, deviceId, deviceName, os, fingerprint}
/// Host -> client: `pair_error`
///   {type, reason: 'wrong_pin' | 'too_many_attempts', attemptsLeft}
///
/// Security model: one-way TLS. The PIN is never sent in the clear —
/// it travels inside the TLS channel. The host's self-signed
/// certificate is trusted on first use (TOFU) and authenticated by the
/// PIN; both sides then pin each other's certificate fingerprint, so a
/// later connection with a different certificate is rejected. This is
/// not mutual TLS: the host authenticates the client by the PIN, the
/// client authenticates the host by the PIN + pinned fingerprint.
class PairingClient {
  /// Pairs with [peer] using the PIN shown on the peer's screen.
  ///
  /// On success the pairing (including the peer's pinned fingerprint)
  /// is stored in [store] and returned. Throws [PairingException] on
  /// a wrong PIN, lockout, fingerprint mismatch, timeout or any
  /// connection problem.
  static Future<PairedDevice> pair({
    required PeerDevice peer,
    required String pin,
    required DeviceIdentity identity,
    required PairingStore store,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final PairedDevice? known = store.findById(peer.deviceId);
    final String? expectedFingerprint = known?.fingerprint;
    String? presentedFingerprint;

    late final SecureSocket socket;
    try {
      socket = await SecureSocket.connect(
        peer.ipAddress,
        peer.port,
        context: buildClientContext(),
        timeout: timeout,
        onBadCertificate: (X509Certificate cert) {
          presentedFingerprint = sha256.convert(cert.der).toString();
          // First pairing: trust on first use, the PIN authenticates
          // the peer. Reconnect: only the pinned fingerprint is OK.
          if (expectedFingerprint == null) return true;
          return presentedFingerprint == expectedFingerprint;
        },
      );
    } on HandshakeException {
      if (expectedFingerprint != null) {
        throw PairingException(
          PairingFailure.fingerprintMismatch,
          'The peer certificate fingerprint changed. '
          'This can mean the other device was reinstalled — or someone '
          'is impersonating it. Unpair it in Settings and pair again '
          'only if you trust this device.',
        );
      }
      throw PairingException(
        PairingFailure.connectionFailed,
        'TLS handshake failed. Is BridgeDesk running on the other '
        'device on the same Wi-Fi?',
      );
    } on TimeoutException {
      throw PairingException(
        PairingFailure.timeout,
        'Timed out connecting to ${peer.ipAddress}:${peer.port}.',
      );
    } on SocketException catch (e) {
      throw PairingException(
        PairingFailure.connectionFailed,
        'Could not connect to ${peer.ipAddress}:${peer.port} (${e.message}).',
      );
    }

    final SecureChannel channel = SecureChannel.attach(socket);
    try {
      // Subscribe BEFORE sending: the channel is a broadcast stream,
      // so a reply arriving before any listener would be dropped.
      final Future<Map<String, dynamic>> replyFuture =
          channel.messages.first;
      await channel.send(<String, dynamic>{
        'type': 'pair_request',
        'deviceId': identity.deviceId,
        'deviceName': identity.deviceName,
        'os': identity.os,
        'port': bridgeDeskPort,
        'pin': pin,
        'fingerprint': identity.fingerprint,
      });
      final Map<String, dynamic> reply;
      try {
        reply = await replyFuture.timeout(timeout);
      } on StateError {
        throw PairingException(
          PairingFailure.connectionFailed,
          'The other device closed the connection without replying.',
        );
      }
      if (reply['type'] == 'pair_ok') {
        final String? hostFingerprint = reply['fingerprint'] as String?;
        if (hostFingerprint == null ||
            hostFingerprint != presentedFingerprint) {
          throw PairingException(
            PairingFailure.fingerprintMismatch,
            'The peer certificate fingerprint changed. '
            'Unpair it in Settings and pair again only if you trust '
            'this device.',
          );
        }
        final PairedDevice paired = PairedDevice(
          deviceId: reply['deviceId'] as String,
          name: reply['deviceName'] as String? ?? peer.name,
          os: reply['os'] as String? ?? peer.os,
          ipAddress: peer.ipAddress,
          port: peer.port,
          fingerprint: hostFingerprint,
          pairedAt: DateTime.now(),
        );
        await store.add(paired);
        return paired;
      }
      if (reply['type'] == 'pair_error') {
        final String reason = reply['reason'] as String? ?? 'wrong_pin';
        final int attemptsLeft =
            (reply['attemptsLeft'] as num?)?.toInt() ?? 0;
        if (reason == 'too_many_attempts') {
          throw PairingException(
            PairingFailure.tooManyAttempts,
            'Too many wrong PIN attempts. Ask the other device to '
            'generate a fresh PIN.',
            attemptsLeft: 0,
          );
        }
        throw PairingException(
          PairingFailure.wrongPin,
          'Wrong PIN. $attemptsLeft attempt(s) left.',
          attemptsLeft: attemptsLeft,
        );
      }
      throw PairingException(
        PairingFailure.connectionFailed,
        'Unexpected reply from the other device.',
      );
    } on TimeoutException {
      throw PairingException(
        PairingFailure.timeout,
        'The other device did not answer the pairing request in time.',
      );
    } finally {
      await channel.close();
    }
  }
}

/// Connects to an already-paired device, accepting only its pinned
/// certificate fingerprint. Used by M2/M3 to open the control channel
/// to a trusted peer. Throws [PairingException] with
/// [PairingFailure.fingerprintMismatch] when the certificate changed.
Future<SecureSocket> connectPinned({
  required String host,
  required int port,
  required String expectedFingerprint,
  Duration timeout = const Duration(seconds: 10),
}) async {
  try {
    return await SecureSocket.connect(
      host,
      port,
      context: buildClientContext(),
      timeout: timeout,
      onBadCertificate: (X509Certificate cert) {
        return sha256.convert(cert.der).toString() == expectedFingerprint;
      },
    );
  } on HandshakeException {
    throw PairingException(
      PairingFailure.fingerprintMismatch,
      'The peer certificate fingerprint changed. '
      'Unpair it in Settings and pair again only if you trust this device.',
    );
  }
}

/// What the host side reports to the UI.
enum PairingHostEventKind { paired, lockout }

class PairingHostEvent {
  const PairingHostEvent(this.kind, this.peer);
  final PairingHostEventKind kind;
  final PairedDevice? peer;
}

/// The host side of pairing: generates a fresh PIN, listens on the TLS
/// port, verifies the PIN the client sends (max 3 attempts per session,
/// then the session locks out and a fresh PIN is required).
class PairingHostSession {
  PairingHostSession._(
    this.pin,
    this._server,
    this._store,
    this._identity,
    this._verifier,
  );

  /// Starts listening. [port] defaults to [bridgeDeskPort]; pass 0 in
  /// tests for an ephemeral port (see [port]).
  static Future<PairingHostSession> start({
    required DeviceIdentity identity,
    required PairingStore store,
    int port = bridgeDeskPort,
  }) async {
    final String pin = PinGenerator.generate();
    final SecureServerSocket server = await SecureServerSocket.bind(
      InternetAddress.anyIPv4,
      port,
      buildServerContext(identity),
    );
    final PairingHostSession session = PairingHostSession._(
      pin,
      server,
      store,
      identity,
      PinVerifier(expectedPin: pin),
    );
    session._listen();
    return session;
  }

  /// The fresh PIN for this session. Show it on screen; never log it.
  final String pin;

  final SecureServerSocket _server;
  final PairingStore _store;
  final DeviceIdentity _identity;
  final PinVerifier _verifier;
  final StreamController<PairingHostEvent> _events =
      StreamController<PairingHostEvent>.broadcast();

  /// Actual listening port (differs from the requested one when 0 was
  /// passed for an ephemeral port).
  int get port => _server.port;

  bool get lockedOut => _verifier.lockedOut;

  /// Emits [PairingHostEventKind.paired] on success and
  /// [PairingHostEventKind.lockout] when the session locks out.
  Stream<PairingHostEvent> get events => _events.stream;

  Future<void> stop() async {
    await _server.close();
    await _events.close();
  }

  void _listen() {
    _server.listen(_handleConnection);
  }

  Future<void> _handleConnection(SecureSocket socket) async {
    final SecureChannel channel = SecureChannel.attach(socket);
    try {
      await for (final Map<String, dynamic> message
          in channel.messages.timeout(const Duration(seconds: 60))) {
        if (message['type'] != 'pair_request') continue;
        if (_verifier.lockedOut) {
          await channel.send(<String, dynamic>{
            'type': 'pair_error',
            'reason': 'too_many_attempts',
            'attemptsLeft': 0,
          });
          await channel.close();
          return;
        }
        final String candidate = message['pin'] as String? ?? '';
        if (!_verifier.verify(candidate)) {
          final int left = _verifier.attemptsLeft;
          await channel.send(<String, dynamic>{
            'type': 'pair_error',
            'reason': left == 0 ? 'too_many_attempts' : 'wrong_pin',
            'attemptsLeft': left,
          });
          if (left == 0) {
            _events.add(
              const PairingHostEvent(PairingHostEventKind.lockout, null),
            );
            await channel.close();
          }
          continue;
        }
        final PairedDevice peer = PairedDevice(
          deviceId: message['deviceId'] as String? ?? 'unknown',
          name: message['deviceName'] as String? ?? 'Unknown device',
          os: message['os'] as String? ?? 'Unknown',
          ipAddress: socket.remoteAddress.address,
          port: (message['port'] as num?)?.toInt() ?? bridgeDeskPort,
          fingerprint: message['fingerprint'] as String? ?? '',
          pairedAt: DateTime.now(),
        );
        await _store.add(peer);
        await channel.send(<String, dynamic>{
          'type': 'pair_ok',
          'deviceId': _identity.deviceId,
          'deviceName': _identity.deviceName,
          'os': _identity.os,
          'fingerprint': _identity.fingerprint,
        });
        _events.add(PairingHostEvent(PairingHostEventKind.paired, peer));
        await channel.close();
        return;
      }
    } catch (_) {
      // Client went away, timed out, or sent garbage: just close.
    } finally {
      await channel.close();
    }
  }
}
