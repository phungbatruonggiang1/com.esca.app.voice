import 'package:flutter/material.dart';

import 'kit/theme.dart';
import 'kit/widgets.dart';
import 'voice.dart';
import 'voice_screen.dart';

void main() {
  final controller = VoiceController(DBusVoiceBackend());
  runApp(VoiceApp(
    controller: controller,
    // A session left open would keep the microphone and the server busy
    // after the screen that started it is gone.
    onBack: () async {
      if (controller.phase != 'idle') await controller.stop();
      closeApplication();
    },
  ));
}

class VoiceApp extends StatelessWidget {
  const VoiceApp({super.key, required this.controller, required this.onBack});

  final VoiceController controller;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voice Assistant',
      debugShowCheckedModeBanner: false,
      theme: escaTheme(),
      home: VoiceScreen(controller: controller, onBack: onBack),
    );
  }
}
