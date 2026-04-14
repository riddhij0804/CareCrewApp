import 'package:carecrew_app/src/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows Firebase setup guidance when Firebase is unavailable', (WidgetTester tester) async {
    await tester.pumpWidget(const CareCrewApp(firebaseInitError: 'test-error'));

    expect(find.text('Firebase needs configuration'), findsOneWidget);
    expect(find.textContaining('test-error'), findsOneWidget);
  });
}
