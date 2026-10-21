import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'kit/theme.dart';
import 'kit/widgets.dart';
import 'voice.dart';

class VoiceScreen extends StatelessWidget {
  const VoiceScreen({super.key, required this.controller, required this.onBack});

  final VoiceController controller;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: EscaBackground(
        child: SafeArea(
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => Padding(
              padding: const EdgeInsets.fromLTRB(40, 32, 40, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  EscaTopBar(
                    icon: Icons.mic_rounded,
                    title: 'Voice Assistant',
                    subtitle: 'Speech recognition and read-back through the AI server',
                    onBack: onBack,
                    trailing: [_PhasePill(phase: controller.phase)],
                  ),
                  FaultBanner(message: controller.error),
                  const SizedBox(height: 28),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(flex: 6, child: _Stage(controller: controller)),
                        const SizedBox(width: 24),
                        Expanded(
                          flex: 5,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _HeardCard(controller: controller),
                              const SizedBox(height: 20),
                              Expanded(child: _HistoryCard(controller: controller)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PhasePill extends StatelessWidget {
  const _PhasePill({required this.phase});

  final String phase;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (phase) {
      'preparing' => ('Preparing', EscaColors.warn),
      'prompting' => ('Playing prompt', EscaColors.warn),
      'listening' => ('Listening', EscaColors.accent),
      'transcribing' => ('Transcribing', EscaColors.violet),
      _ => ('Ready', EscaColors.textDim),
    };
    return StatusPill(label: label, color: color, live: phase != 'idle');
  }
}

/// The left half: the button, which becomes a live microphone only once the
/// service says it is one.
class _Stage extends StatelessWidget {
  const _Stage({required this.controller});

  final VoiceController controller;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final phase = controller.phase;
    final listening = phase == 'listening';

    final title = switch (phase) {
      'preparing' => 'Preparing…',
      'prompting' => 'Listen to the prompt…',
      'listening' => controller.speaking ? 'Listening…' : 'Speak now',
      'transcribing' => 'Transcribing…',
      _ => 'Press to talk',
    };

    return EscaCard(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 28),
      child: Column(
        children: [
          const Spacer(flex: 2),
          _MicOrb(controller: controller),
          const SizedBox(height: 32),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(title, key: ValueKey(title), style: text.headlineMedium),
          ),
          const SizedBox(height: 10),
          _Hint(controller: controller),
          const Spacer(),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 300),
            opacity: listening ? 1 : 0.35,
            child: SizedBox(
              height: 150,
              width: double.infinity,
              child: RepaintBoundary(
                child: CustomPaint(painter: _WaveformPainter(controller)),
              ),
            ),
          ),
          const SizedBox(height: 24),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: phase == 'idle'
                ? const SizedBox(height: 52)
                : OutlinedButton.icon(
                    onPressed: controller.stop,
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('Stop'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: EscaColors.text,
                      side: const BorderSide(color: EscaColors.borderStrong),
                      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                      shape: const StadiumBorder(),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.controller});

  final VoiceController controller;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(color: EscaColors.textDim);
    final since = controller.listeningSince;

    // The service gives up if nobody talks. Counting that down keeps a
    // silent screen from looking like a broken one.
    if (controller.phase == 'listening' && !controller.speaking && since != null) {
      return StreamBuilder<int>(
        stream: Stream.periodic(const Duration(milliseconds: 250), (i) => i),
        builder: (context, _) {
          final left = VoiceController.waitForSpeech - DateTime.now().difference(since);
          final seconds = left.inSeconds.clamp(0, 99);
          return Text('Stops in ${seconds}s if nobody speaks', style: style);
        },
      );
    }

    final hint = switch (controller.phase) {
      'preparing' => 'Checking the AI server and opening the microphone',
      'prompting' => 'The microphone opens right after the prompt',
      'listening' => 'Stop speaking to end the sentence',
      'transcribing' => 'Sending the recording to the AI server',
      _ => 'The microphone opens only once the AI server is ready',
    };
    return Text(hint, style: style);
  }
}

/// The button. Teal and inviting when idle, a spinning ring while the
/// service prepares, glowing with the voice while listening.
class _MicOrb extends StatefulWidget {
  const _MicOrb({required this.controller});

  final VoiceController controller;

  @override
  State<_MicOrb> createState() => _MicOrbState();
}

class _MicOrbState extends State<_MicOrb> with SingleTickerProviderStateMixin {
  // Spins only while the service is busy. A controller left repeating would
  // keep the engine drawing every vsync with nothing on screen changing.
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  bool _hover = false;

  static bool _busy(String phase) =>
      phase == 'preparing' || phase == 'prompting' || phase == 'transcribing';

  void _syncSpin() {
    if (_busy(widget.controller.phase)) {
      if (!_spin.isAnimating) _spin.repeat();
    } else if (_spin.isAnimating) {
      _spin.stop();
    }
  }

  @override
  void initState() {
    super.initState();
    _syncSpin();
  }

  @override
  void didUpdateWidget(_MicOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncSpin();
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final phase = c.phase;
    final idle = phase == 'idle';
    final busy = _busy(phase);
    final color = switch (phase) {
      'preparing' || 'prompting' => EscaColors.warn,
      'transcribing' => EscaColors.violet,
      _ => EscaColors.accent,
    };
    const size = 220.0;

    return MouseRegion(
      cursor: idle ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: idle ? c.talk : null,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 160),
          scale: idle && _hover ? 1.04 : 1.0,
          child: SizedBox(
            width: size + 60,
            height: size + 60,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // The voice itself, as a glow that swells with the level.
                ValueListenableBuilder<int>(
                  valueListenable: c.levelTick,
                  builder: (context, tick, child) {
                    final levels = c.levels;
                    final level = phase == 'listening' && levels.isNotEmpty
                        ? _loudness(levels.last, c.floorDb)
                        : 0.0;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 90),
                      width: size + 56 * level,
                      height: size + 56 * level,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color.withValues(alpha: 0.10 + 0.12 * level),
                      ),
                    );
                  },
                ),
                if (busy)
                  RotationTransition(
                    turns: _spin,
                    child: SizedBox(
                      width: size + 20,
                      height: size + 20,
                      child: CircularProgressIndicator(
                        value: 0.28,
                        strokeWidth: 4,
                        color: color,
                        strokeCap: StrokeCap.round,
                      ),
                    ),
                  ),
                if (phase == 'listening' && c.listeningSince != null && !c.speaking)
                  _CountdownRing(since: c.listeningSince!, size: size + 20, color: color),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: size - 40,
                  height: size - 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: idle || phase == 'listening'
                          ? [color, Color.lerp(color, EscaColors.info, 0.5)!]
                          : [EscaColors.surfaceHigh, EscaColors.surface],
                    ),
                    border: Border.all(color: color.withValues(alpha: 0.6), width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: idle && _hover ? 0.55 : 0.30),
                        blurRadius: 40,
                      ),
                    ],
                  ),
                  child: Icon(
                    switch (phase) {
                      'transcribing' => Icons.auto_awesome_rounded,
                      'prompting' => Icons.volume_up_rounded,
                      'preparing' => Icons.hourglass_top_rounded,
                      _ => Icons.mic_rounded,
                    },
                    size: 76,
                    color: idle || phase == 'listening' ? const Color(0xFF02201D) : color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 0..1: how far the level stands above the room, on the same scale the
/// waveform uses.
double _loudness(double db, double floorDb) {
  final bottom = math.min(floorDb - 6, -60.0);
  return ((db - bottom) / (0 - bottom)).clamp(0.0, 1.0);
}

class _CountdownRing extends StatefulWidget {
  const _CountdownRing({required this.since, required this.size, required this.color});

  final DateTime since;
  final double size;
  final Color color;

  @override
  State<_CountdownRing> createState() => _CountdownRingState();
}

class _CountdownRingState extends State<_CountdownRing> with SingleTickerProviderStateMixin {
  late final AnimationController _left = AnimationController(
    vsync: this,
    duration: VoiceController.waitForSpeech,
  );

  @override
  void initState() {
    super.initState();
    final elapsed = DateTime.now().difference(widget.since).inMilliseconds /
        VoiceController.waitForSpeech.inMilliseconds;
    _left
      ..value = elapsed.clamp(0.0, 1.0)
      ..forward();
  }

  @override
  void dispose() {
    _left.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _left,
      builder: (context, _) => SizedBox(
        width: widget.size,
        height: widget.size,
        child: CircularProgressIndicator(
          value: 1 - _left.value,
          strokeWidth: 4,
          color: widget.color,
          backgroundColor: widget.color.withValues(alpha: 0.12),
          strokeCap: StrokeCap.round,
        ),
      ),
    );
  }
}

/// Recent levels as mirrored bars, drawn between the room's own noise floor
/// and 0 dBFS so a loud room does not peg it full. A bar turns teal once it
/// clears the floor by the margin that counts as speech, which makes the
/// detector's decision visible.
class _WaveformPainter extends CustomPainter {
  _WaveformPainter(this.controller) : super(repaint: controller.levelTick);

  final VoiceController controller;

  /// esca-voiced's speech margin above the floor.
  static const _speechMarginDb = 9.0;

  @override
  void paint(Canvas canvas, Size size) {
    final levels = controller.levels;
    final floor = controller.floorDb;
    const count = VoiceController.levelHistory;
    final slot = size.width / count;
    final barWidth = math.max(2.0, slot * 0.55);
    final mid = size.height / 2;

    final quiet = Paint()..color = EscaColors.textFaint.withValues(alpha: 0.55);
    final loud = Paint()..color = EscaColors.accent;

    for (var i = 0; i < count; i++) {
      final index = levels.length - count + i;
      final db = index >= 0 ? levels[index] : -120.0;
      final half = math.max(2.0, _loudness(db, floor) * (mid - 4));
      final x = i * slot + (slot - barWidth) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(x, mid - half, x + barWidth, mid + half),
          Radius.circular(barWidth / 2),
        ),
        index >= 0 && db > floor + _speechMarginDb ? loud : quiet,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter old) => old.controller != controller;
}

class _HeardCard extends StatelessWidget {
  const _HeardCard({required this.controller});

  final VoiceController controller;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final t = controller.latest;
    return EscaCard(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('HEARD', style: text.labelSmall),
              const Spacer(),
              if (t != null) ...[
                _Chip(t.language.toUpperCase()),
                const SizedBox(width: 8),
                _Chip('${t.ms.toStringAsFixed(0)} ms'),
              ],
            ],
          ),
          const SizedBox(height: 18),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Text(
              t == null
                  ? 'Nothing yet. Press the microphone and say something.'
                  : (t.text.isEmpty ? '(nothing heard)' : '“${t.text}”'),
              key: ValueKey(t?.at),
              style: t == null
                  ? text.titleMedium?.copyWith(color: EscaColors.textFaint)
                  : text.headlineSmall?.copyWith(height: 1.35),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (t != null) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Text('Confidence', style: text.bodySmall),
                const SizedBox(width: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: t.confidence.clamp(0.0, 1.0),
                      minHeight: 6,
                      color: EscaColors.accent,
                      backgroundColor: EscaColors.border,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text('${(t.confidence * 100).toStringAsFixed(0)}%', style: text.titleSmall),
              ],
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: t == null || t.text.isEmpty ? null : controller.sayBack,
            icon: const Icon(Icons.volume_up_rounded),
            label: const Text('Read back'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
              shape: const StadiumBorder(),
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: EscaColors.surfaceHigh,
        borderRadius: BorderRadius.circular(EscaRadius.pill),
        border: Border.all(color: EscaColors.border),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.controller});

  final VoiceController controller;

  static String _time(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final older = controller.heard.skip(1).toList();
    return EscaCard(
      padding: const EdgeInsets.fromLTRB(28, 24, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Earlier sentences', style: text.titleMedium),
          const SizedBox(height: 8),
          Expanded(
            child: older.isEmpty
                ? Center(
                    child: Text('Sentences you say will appear here',
                        style: text.bodyMedium?.copyWith(color: EscaColors.textFaint)),
                  )
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: older.length,
                    separatorBuilder: (context, i) =>
                        const Divider(height: 1, color: EscaColors.border),
                    itemBuilder: (context, i) {
                      final t = older[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Text(_time(t.at), style: text.bodySmall),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(t.text.isEmpty ? '(nothing heard)' : t.text,
                                  style: text.bodyLarge, overflow: TextOverflow.ellipsis),
                            ),
                            IconButton(
                              tooltip: 'Read this back',
                              onPressed: t.text.isEmpty ? null : () => controller.sayBack(t),
                              icon: const Icon(Icons.volume_up_outlined, size: 20),
                              color: EscaColors.textDim,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
