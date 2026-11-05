// BridgeDesk M0 smoke test: the app boots and shows its three tabs.

import 'package:bridgedesk/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('BridgeDesk shell shows Devices, Pairing and Settings',
      (WidgetTester tester) async {
    await tester.pumpWidget(const BridgeDeskApp());
    // DevicesScreen searches on start (async stub); let it finish so
    // the empty state renders instead of "Searching on LAN…".
    await tester.pumpAndSettle();

    expect(find.text('BridgeDesk'), findsWidgets);
    expect(find.text('Devices'), findsOneWidget);
    expect(find.text('Pairing'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('No devices found yet'), findsOneWidget);
  });
}
