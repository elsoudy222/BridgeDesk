import 'dart:convert';
import 'dart:typed_data';

import '../constants.dart';

/// Length-prefixed framing for JSON control messages on the TLS channel.
///
/// Wire format: 4-byte big-endian payload length, then that many UTF-8
/// bytes of a JSON object. M2/M3 reuse this for mouse/clipboard/file
/// control messages; file *payloads* (M3) travel chunked, not as one
/// giant control message, which is why oversized frames are rejected
/// instead of buffered.
class FramingException implements Exception {
  FramingException(this.message);
  final String message;

  @override
  String toString() => 'FramingException: $message';
}

/// Encodes one JSON control message to its framed bytes.
Uint8List encodeMessage(Map<String, dynamic> message) {
  final List<int> payload = utf8.encode(jsonEncode(message));
  if (payload.length > bridgeDeskMaxMessageBytes) {
    throw FramingException(
      'Message is $payload.length bytes, over the '
      '$bridgeDeskMaxMessageBytes-byte limit.',
    );
  }
  final ByteData header = ByteData(4)
    ..setUint32(0, payload.length, Endian.big);
  final Uint8List out =
      Uint8List(header.lengthInBytes + payload.length);
  out.setRange(0, 4, header.buffer.asUint8List());
  out.setRange(4, out.length, payload);
  return out;
}

/// Stateful decoder: feed socket chunks to [add], get back every
/// complete message decoded so far. Throws [FramingException] on an
/// oversized length prefix or invalid JSON.
class MessageFramer {
  final BytesBuilder _buffer = BytesBuilder(copy: false);

  /// Number of bytes currently buffered (undecoded).
  int get bufferedBytes => _buffer.length;

  List<Map<String, dynamic>> add(List<int> chunk) {
    _buffer.add(chunk);
    final List<Map<String, dynamic>> messages = <Map<String, dynamic>>[];
    while (true) {
      final Uint8List bytes = _buffer.toBytes();
      if (bytes.length < 4) return messages;
      final int length =
          ByteData.sublistView(bytes, 0, 4).getUint32(0, Endian.big);
      if (length > bridgeDeskMaxMessageBytes) {
        throw FramingException(
          'Peer announced a $length-byte message, over the '
          '$bridgeDeskMaxMessageBytes-byte limit.',
        );
      }
      if (bytes.length < 4 + length) return messages;
      final String jsonText =
          utf8.decode(bytes.sublist(4, 4 + length));
      final Object? decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) {
        throw FramingException('Control message is not a JSON object.');
      }
      messages.add(decoded);
      _buffer.clear();
      if (bytes.length > 4 + length) {
        _buffer.add(bytes.sublist(4 + length));
      }
    }
  }
}
