import 'package:flutter_test/flutter_test.dart';
import 'package:video_bit_mobile/main.dart';

void main() {
  testWidgets('shows the single-purpose converter interface', (tester) async {
    await tester.pumpWidget(const BitShiftApp());
    expect(find.text('BITSHIFT'), findsOneWidget);
    expect(find.text('SELECT VIDEO'), findsOneWidget);
    expect(find.text('CHANGE BITRATE'), findsOneWidget);
  });
}
