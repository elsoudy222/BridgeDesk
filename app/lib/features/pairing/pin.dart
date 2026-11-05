import 'dart:math';

import '../../core/constants.dart';

/// 6-digit pairing PINs.
///
/// The host generates a fresh PIN per pairing session; the client types
/// what it sees on the host's screen. Nothing is ever hard-coded.
class PinGenerator {
  /// A random [bridgeDeskPinLength]-digit PIN, zero-padded
  /// (so `000042` is a valid PIN). Uses [Random.secure].
  static String generate({Random? random}) {
    final Random source = random ?? Random.secure();
    final int value = source.nextInt(1000000);
    return value.toString().padLeft(bridgeDeskPinLength, '0');
  }

  /// True when [pin] is exactly 6 decimal digits.
  static bool isWellFormed(String pin) {
    if (pin.length != bridgeDeskPinLength) return false;
    return int.tryParse(pin) != null;
  }
}

/// Compares two strings without leaking, through timing, how many
/// leading characters matched. Always scans the shorter length and
/// folds the length difference into the result.
bool constantTimeEquals(String a, String b) {
  final List<int> aUnits = a.codeUnits;
  final List<int> bUnits = b.codeUnits;
  var diff = aUnits.length ^ bUnits.length;
  final int length =
      aUnits.length < bUnits.length ? aUnits.length : bUnits.length;
  for (var i = 0; i < length; i++) {
    diff |= aUnits[i] ^ bUnits[i];
  }
  return diff == 0;
}

/// One pairing session's PIN check: at most [maxAttempts] wrong
/// guesses, then it locks out and the host must generate a fresh PIN.
/// A correct guess after some wrong guesses still succeeds, as long as
/// the session is not locked out.
class PinVerifier {
  PinVerifier({
    required this.expectedPin,
    this.maxAttempts = bridgeDeskMaxPinAttempts,
  });

  final String expectedPin;
  final int maxAttempts;
  int _attemptsUsed = 0;

  int get attemptsUsed => _attemptsUsed;
  int get attemptsLeft => maxAttempts - _attemptsUsed;
  bool get lockedOut => _attemptsUsed >= maxAttempts;

  /// Returns true on a correct PIN. Returns false (and counts an
  /// attempt) on a wrong one, and also false once locked out.
  bool verify(String candidate) {
    if (lockedOut) return false;
    _attemptsUsed++;
    return constantTimeEquals(candidate, expectedPin);
  }
}
