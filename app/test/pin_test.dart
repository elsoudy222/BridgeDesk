import 'dart:math';

import 'package:bridgedesk/features/pairing/pin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PinGenerator', () {
    test('generates a 6-digit numeric PIN', () {
      for (var i = 0; i < 100; i++) {
        final String pin = PinGenerator.generate();
        expect(pin.length, 6);
        expect(int.tryParse(pin), isNotNull);
        expect(PinGenerator.isWellFormed(pin), isTrue);
      }
    });

    test('generates different PINs (not a fixed value)', () {
      final Set<String> pins = <String>{
        for (var i = 0; i < 50; i++) PinGenerator.generate(),
      };
      expect(pins.length, greaterThan(40));
    });

    test('isWellFormed rejects bad input', () {
      expect(PinGenerator.isWellFormed('12345'), isFalse);
      expect(PinGenerator.isWellFormed('1234567'), isFalse);
      expect(PinGenerator.isWellFormed('abcdef'), isFalse);
      expect(PinGenerator.isWellFormed(''), isFalse);
      expect(PinGenerator.isWellFormed('000000'), isTrue);
      expect(PinGenerator.isWellFormed('999999'), isTrue);
    });

    test('generate accepts a seeded Random for tests', () {
      final String a = PinGenerator.generate(random: Random(42));
      final String b = PinGenerator.generate(random: Random(42));
      expect(a, b);
    });
  });

  group('constantTimeEquals', () {
    test('equal strings compare true, different ones false', () {
      expect(constantTimeEquals('123456', '123456'), isTrue);
      expect(constantTimeEquals('123456', '123457'), isFalse);
      expect(constantTimeEquals('123456', '12345'), isFalse);
      expect(constantTimeEquals('', ''), isTrue);
      expect(constantTimeEquals('a', ''), isFalse);
    });
  });

  group('PinVerifier', () {
    test('correct PIN succeeds on first try', () {
      final PinVerifier verifier = PinVerifier(expectedPin: '482910');
      expect(verifier.verify('482910'), isTrue);
      expect(verifier.attemptsUsed, 1);
      expect(verifier.lockedOut, isFalse);
    });

    test('correct PIN still succeeds after wrong guesses', () {
      final PinVerifier verifier = PinVerifier(expectedPin: '482910');
      expect(verifier.verify('000000'), isFalse);
      expect(verifier.verify('111111'), isFalse);
      expect(verifier.attemptsLeft, 1);
      expect(verifier.verify('482910'), isTrue);
    });

    test('locks out after 3 wrong guesses', () {
      final PinVerifier verifier = PinVerifier(expectedPin: '482910');
      expect(verifier.verify('000000'), isFalse);
      expect(verifier.verify('111111'), isFalse);
      expect(verifier.verify('222222'), isFalse);
      expect(verifier.lockedOut, isTrue);
      expect(verifier.attemptsLeft, 0);
      // Even the right PIN no longer works once locked out.
      expect(verifier.verify('482910'), isFalse);
    });

    test('attempts are counted even after lockout', () {
      final PinVerifier verifier =
          PinVerifier(expectedPin: '482910', maxAttempts: 2);
      verifier.verify('000000');
      verifier.verify('000000');
      expect(verifier.lockedOut, isTrue);
      verifier.verify('000000');
      expect(verifier.attemptsUsed, 2);
    });
  });
}
