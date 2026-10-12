import 'package:flutter_test/flutter_test.dart';
import 'package:video_creator_ai/main.dart';

void main() {
  testWidgets('App arranca', (WidgetTester tester) async {
    await tester.pumpWidget(const VideoCreatorApp());
    expect(find.textContaining('Video Creator AI'), findsOneWidget);
  });
}
