import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../identity/device_identity.dart';
import 'framing.dart';

/// A TLS socket plus length-prefixed JSON control messages.
///
/// M2/M3 send their control messages (mouse, clipboard, file headers)
/// through this same channel. The channel itself knows nothing about
/// pairing — see `features/pairing/pairing_service.dart` for the
/// handshake that runs over it.
class SecureChannel {
  SecureChannel._(this._socket, this._messages);

  /// Wraps an already-connected [SecureSocket]; incoming bytes are
  /// framed and decoded into [messages].
  static SecureChannel attach(SecureSocket socket) {
    final StreamController<Map<String, dynamic>> controller =
        StreamController<Map<String, dynamic>>.broadcast();
    final MessageFramer framer = MessageFramer();
    socket.listen(
      (List<int> data) {
        try {
          for (final Map<String, dynamic> message in framer.add(data)) {
            controller.add(message);
          }
        } catch (e) {
          controller.addError(e);
        }
      },
      onError: controller.addError,
      onDone: controller.close,
    );
    return SecureChannel._(socket, controller.stream);
  }

  final SecureSocket _socket;
  final Stream<Map<String, dynamic>> _messages;

  /// Decoded control messages from the peer.
  Stream<Map<String, dynamic>> get messages => _messages;

  /// The peer's IP address, for logging / storing the pairing.
  String get remoteAddress => _socket.remoteAddress.address;

  /// Sends one JSON control message.
  Future<void> send(Map<String, dynamic> message) async {
    _socket.add(encodeMessage(message));
    await _socket.flush();
  }

  Future<void> close() async {
    try {
      await _socket.close();
    } catch (_) {
      // Already closed; nothing to do.
    }
  }
}

/// Server context for our own self-signed certificate.
SecurityContext buildServerContext(DeviceIdentity identity) {
  final SecurityContext context = SecurityContext();
  context.useCertificateChainBytes(
    utf8.encode(identity.certificatePem),
  );
  context.usePrivateKeyBytes(utf8.encode(identity.privateKeyPem));
  return context;
}

/// Client context for self-signed peers: no trusted roots, so every
/// certificate is checked by the caller's `onBadCertificate` callback
/// (fingerprint pinning / trust-on-first-use), never by a CA.
SecurityContext buildClientContext() =>
    SecurityContext(withTrustedRoots: false);
