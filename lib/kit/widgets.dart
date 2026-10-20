// Building blocks every ESCA screen is made of. See theme.dart for why this
// directory is copied rather than shared.

import 'dart:io' show exit;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Ends the application. Each one is its own homescreen process started by
/// esca-appmanagerd; leaving means exiting, which uncovers ESCA Home beneath
/// it and lets the manager report the instance as stopped.
Never closeApplication() => exit(0);

/// The backdrop behind every screen: near-black with a faint wash of the
/// screen's own colour from the top left, so the four applications read as
/// one family without looking identical.
class EscaBackground extends StatelessWidget {
  const EscaBackground({super.key, required this.child, this.tint = EscaColors.accent});

  final Widget child;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    // Expanded to the whole screen: sized by a short child, the wash would
    // end in a hard edge partway down.
    return SizedBox.expand(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.9, -1.1),
            radius: 1.6,
            colors: [
              Color.lerp(EscaColors.backgroundRaised, tint, 0.10)!,
              EscaColors.background,
            ],
          ),
        ),
        child: child,
      ),
    );
  }
}

/// A rounded surface with a hairline border. Interactive when given [onTap]:
/// the border lights up under the pointer, which on a board driven by a mouse
/// is the only hint that something can be clicked.
class EscaCard extends StatefulWidget {
  const EscaCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
    this.highlight,
    this.color = EscaColors.surface,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  /// Draws the border in this colour, for a card that needs attention.
  final Color? highlight;
  final Color color;

  @override
  State<EscaCard> createState() => _EscaCardState();
}

class _EscaCardState extends State<EscaCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null;
    final borderColor = widget.highlight ??
        (interactive && _hover ? EscaColors.accent.withValues(alpha: 0.6) : EscaColors.border);
    final radius = BorderRadius.circular(EscaRadius.card);

    return MouseRegion(
      cursor: interactive ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: interactive ? (_) => setState(() => _hover = true) : null,
      onExit: interactive ? (_) => setState(() => _hover = false) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: interactive && _hover ? EscaColors.surfaceHigh : widget.color,
          borderRadius: radius,
          border: Border.all(color: borderColor, width: 1.2),
          boxShadow: [
            if (widget.highlight != null)
              BoxShadow(
                color: widget.highlight!.withValues(alpha: 0.18),
                blurRadius: 32,
                spreadRadius: 1,
              ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: widget.onTap,
            child: Padding(padding: widget.padding, child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// A square of colour behind an icon: the identity mark of an application or
/// a section.
class IconBadge extends StatelessWidget {
  const IconBadge({
    super.key,
    required this.icon,
    this.color = EscaColors.accent,
    this.size = 44,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.withValues(alpha: 0.32), color.withValues(alpha: 0.12)],
        ),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Icon(icon, color: color, size: size * 0.5),
    );
  }
}

/// The bar across the top of every application other than Home: a way back,
/// what this is, and whatever state belongs beside the title.
class EscaTopBar extends StatelessWidget {
  const EscaTopBar({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.color = EscaColors.accent,
    this.onBack,
    this.trailing = const [],
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  /// Shown as a "Trang chủ" button when set.
  final VoidCallback? onBack;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        if (onBack != null) ...[
          BackPill(onPressed: onBack!),
          const SizedBox(width: 20),
        ],
        IconBadge(icon: icon, color: color, size: 48),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: text.titleLarge, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(subtitle, style: text.bodySmall, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        for (final widget in trailing) ...[const SizedBox(width: 12), widget],
      ],
    );
  }
}

class BackPill extends StatelessWidget {
  const BackPill({super.key, required this.onPressed, this.label = 'Trang chủ'});

  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.arrow_back_rounded, size: 20),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: EscaColors.text,
        side: const BorderSide(color: EscaColors.borderStrong),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontFamily: kEscaFontFamily, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// A short state label with a dot, the dot pulsing while [live].
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.live = false,
  });

  final String label;
  final Color color;
  final bool live;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(EscaRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PulseDot(color: color, pulsing: live),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 13,
              fontFamily: kEscaFontFamily,
            ),
          ),
        ],
      ),
    );
  }
}

class PulseDot extends StatefulWidget {
  const PulseDot({super.key, required this.color, this.pulsing = true, this.size = 8});

  final Color color;
  final bool pulsing;
  final double size;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(PulseDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.pulsing && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.pulsing && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return SizedBox(
      width: size * 2.4,
      height: size * 2.4,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;
          return Stack(
            alignment: Alignment.center,
            children: [
              if (widget.pulsing)
                Container(
                  width: size + size * 1.4 * t,
                  height: size + size * 1.4 * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: 0.45 * (1 - t)),
                  ),
                ),
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(shape: BoxShape.circle, color: widget.color),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// One labelled number.
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.unit = '',
    this.icon,
    this.color = EscaColors.text,
  });

  final String label;
  final String value;
  final String unit;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return EscaCard(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: EscaColors.textDim),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(label.toUpperCase(),
                    style: text.labelSmall, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(
                  value,
                  style: text.headlineSmall?.copyWith(
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(unit, style: text.bodySmall),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// A fault from a service, shown until [message] goes empty. Faults are shown,
/// never swallowed: a silent failure looks exactly like a working idle state.
class FaultBanner extends StatelessWidget {
  const FaultBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: message.isEmpty
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 16),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: EscaColors.bad.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(EscaRadius.control),
                border: Border.all(color: EscaColors.bad.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: EscaColors.bad),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      message,
                      style: const TextStyle(color: EscaColors.text),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
