import 'package:flutter_test/flutter_test.dart';

import 'package:example/main.dart';

void main() {
  testWidgets('renders the device scan screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Bluetooth Devices'), findsOneWidget);
    expect(find.text('SCANNED DEVICES'), findsOneWidget);
    expect(find.text('Restart Scan'), findsOneWidget);
  });
}
