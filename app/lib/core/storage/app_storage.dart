import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Where BridgeDesk keeps its local state on disk.
///
/// Production layout (inside the platform app-support directory):
/// ```
/// <support>/bridgedesk/
///   identity/device_id.txt   stable per-device id
///   identity/cert.pem        per-device self-signed TLS certificate
///   identity/key.pem         matching private key (never leaves the device)
///   pairings.json            remembered paired devices + fingerprints
/// ```
/// No cloud, no account: everything lives on the device. Tests pass
/// an [override] directory (usually a temp dir) instead, so unit tests
/// never touch the real app-support directory or platform channels.
class AppStorage {
  /// Returns the `bridgedesk` base directory, creating it if needed.
  ///
  /// The platform call is time-boxed: a method-channel call that never
  /// answers (seen in widget tests, where no platform plugin answers
  /// `path_provider`) must fail fast instead of freezing the UI — the
  /// screens degrade to manual-IP mode when storage is unavailable.
  static Future<Directory> baseDir({Directory? override}) async {
    if (override != null) {
      await override.create(recursive: true);
      return override;
    }
    final Directory support = await getApplicationSupportDirectory()
        .timeout(const Duration(seconds: 5));
    final Directory base = Directory(
      '${support.path}${Platform.pathSeparator}bridgedesk',
    );
    await base.create(recursive: true);
    return base;
  }
}
