import 'package:flutter_test/flutter_test.dart';
import 'package:incredere_voiceai/main.dart';

void main() {
  testWidgets('App renders VoiceChatScreen', (WidgetTester tester) async {
    await tester.pumpWidget(const IncredereVoiceAIApp());
    expect(find.text('Incredere VoiceAI'), findsOneWidget);
  });
}
