/// BridgeDesk M1 constants.
///
/// Single source of truth for the values the two sides must agree on:
/// the mDNS service type, the TCP/TLS port, the PIN rules and the
/// transport limits.
library;

/// mDNS service type advertised and browsed on the LAN.
const String bridgeDeskServiceType = '_bridgedesk._tcp';

/// TCP port the TLS pairing/control channel listens on.
const int bridgeDeskPort = 48150;

/// Pairing PIN: exactly this many decimal digits.
const int bridgeDeskPinLength = 6;

/// Wrong PINs allowed per pairing session before it locks out and the
/// host must generate a fresh PIN.
const int bridgeDeskMaxPinAttempts = 3;

/// Largest single control message (framing) accepted on the channel.
/// File payloads (M3) travel on a separate chunked path, not in a
/// single control message.
const int bridgeDeskMaxMessageBytes = 16 * 1024 * 1024;
