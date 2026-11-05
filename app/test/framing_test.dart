import 'dart:convert';
import 'dart:typed_data';

import 'package:bridgedesk/core/constants.dart';
import 'package:bridgedesk/core/transport/framing.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _msg(String type) => <String, dynamic>{
      'type': type,
      'n': 42,
    };

void main() {
  group('encodeMessage / MessageFramer', () {
    test('round-trip: one message', () {
      final Uint8List bytes = encodeMessage(_msg('ping'));
      final MessageFramer framer = MessageFramer();
      final List<Map<String, dynamic>> out = framer.add(bytes);
      expect(out, <Map<String, dynamic>>[_msg('ping')]);
    });

    test('round-trip: several messages in one chunk', () {
      final Uint8List a = encodeMessage(_msg('one'));
      final Uint8List b = encodeMessage(_msg('two'));
      final Uint8List combined = Uint8List(a.length + b.length)
        ..setRange(0, a.length, a)
        ..setRange(a.length, a.length + b.length, b);
      final MessageFramer framer = MessageFramer();
      expect(
        framer.add(combined),
        <Map<String, dynamic>>[_msg('one'), _msg('two')],
      );
    });

    test('round-trip: message split across many small chunks', () {
      final Uint8List bytes = encodeMessage(_msg('split'));
      final MessageFramer framer = MessageFramer();
      final List<Map<String, dynamic>> all = <Map<String, dynamic>>[];
      for (var i = 0; i < bytes.length; i++) {
        all.addAll(framer.add(bytes.sublist(i, i + 1)));
      }
      expect(all, <Map<String, dynamic>>[_msg('split')]);
      expect(framer.bufferedBytes, 0);
    });

    test('partial header is buffered, not decoded', () {
      final Uint8List bytes = encodeMessage(_msg('partial'));
      final MessageFramer framer = MessageFramer();
      expect(framer.add(bytes.sublist(0, 2)), isEmpty);
      expect(framer.bufferedBytes, 2);
      expect(framer.add(bytes.sublist(2)), <Map<String, dynamic>>[
        _msg('partial'),
      ]);
    });

    test('encode rejects an oversized message', () {
      final String big = 'x' * (bridgeDeskMaxMessageBytes + 1);
      expect(
        () => encodeMessage(<String, dynamic>{'type': 'big', 'data': big}),
        throwsA(isA<FramingException>()),
      );
    });

    test('framer rejects a header claiming an oversized message', () {
      final ByteData header = ByteData(4)
        ..setUint32(0, bridgeDeskMaxMessageBytes + 1, Endian.big);
      final MessageFramer framer = MessageFramer();
      expect(
        () => framer.add(header.buffer.asUint8List()),
        throwsA(isA<FramingException>()),
      );
    });

    test('framer rejects non-JSON-object payloads', () {
      final List<int> payload = utf8.encode('[1, 2, 3]');
      final ByteData header = ByteData(4)
        ..setUint32(0, payload.length, Endian.big);
      final Uint8List bytes = Uint8List(4 + payload.length)
        ..setRange(0, 4, header.buffer.asUint8List())
        ..setRange(4, 4 + payload.length, payload);
      final MessageFramer framer = MessageFramer();
      expect(
        () => framer.add(bytes),
        throwsA(isA<FramingException>()),
      );
    });
  });
}
