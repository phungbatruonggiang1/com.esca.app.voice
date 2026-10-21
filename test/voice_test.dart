import 'dart:async';

import 'package:esca_voice/main.dart';
import 'package:esca_voice/voice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for esca-voiced.
class FakeVoice implements VoiceBackend {
  final calls = <String>[];
  final said = <String>[];
  final controller = StreamController<VoiceEvent>.broadcast();

  @override
  Future<String> phase() async => 'idle';

  @override
  Future<void> startListening() async => calls.add('StartListening');

  @override
  Future<void> stopListening() async => calls.add('StopListening');

  @override
  Future<void> say(String text) async => said.add(text);

  @override
  Stream<VoiceEvent> get events => controller.stream;

  @override
  Future<void> dispose() => controller.close();

  void emit(VoiceEvent event) => controller.add(event);

  void hear(String text) => emit(Heard(Transcript(
      text: text, language: 'vi', confidence: 0.92, ms: 640, at: DateTime(2026, 10, 20, 9, 30))));
}

void voiceTest(String description, Future<void> Function(WidgetTester, FakeVoice) body) {
  testWidgets(description, (tester) async {
    tester.view.physicalSize = const Size(1920, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final backend = FakeVoice();
    final controller = VoiceController(backend);
    await tester.pumpWidget(VoiceApp(controller: controller, onBack: () {}));
    await tester.pump();

    await body(tester, backend);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}

void main() {
  voiceTest('pressing the microphone starts a session', (tester, backend) async {
    expect(find.text('Press to talk'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.mic_rounded).last);
    await tester.pump();
    expect(backend.calls, ['StartListening']);
  });

  voiceTest('the invitation to speak waits for "listening"', (tester, backend) async {
    backend.emit(PhaseChanged('preparing'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Preparing…'), findsOneWidget);
    expect(find.text('Speak now'), findsNothing);

    backend.emit(PhaseChanged('listening'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Speak now'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
  });

  voiceTest('a press while busy does not start a second session', (tester, backend) async {
    backend.emit(PhaseChanged('transcribing'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byIcon(Icons.auto_awesome_rounded));
    await tester.pump();
    expect(backend.calls, isEmpty);
  });

  voiceTest('what was heard is shown and can be read back', (tester, backend) async {
    backend.hear('turn on the living room light');
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('“turn on the living room light”'), findsOneWidget);
    expect(find.text('92%'), findsOneWidget);

    await tester.tap(find.text('Read back'));
    await tester.pump();
    expect(backend.said, ['turn on the living room light']);
  });

  voiceTest('a fault is shown', (tester, backend) async {
    backend.emit(Fault('server: the AI server is not answering'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('server: the AI server is not answering'), findsOneWidget);
  });
}
