import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../l10n/generated/app_localizations.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';

enum VoiceInputState { idle, listening, processing }

/// The large circular mic affordance for the voice-billing flow.
///
/// Communicates its state visually (idle / listening / processing)
/// instead of relying on text alone — a pulsing ring while listening, a
/// spinner while processing — because state needs to be readable at a
/// glance mid-conversation with a customer, not read carefully.
///
/// Stateful: owns the `AnimationController` driving the pulse and disposes
/// it — genuine internal state, not prop passthrough.
class VoiceInputButton extends StatefulWidget {
  final VoiceInputState state;
  final VoidCallback? onTap;
  final double size;

  const VoiceInputButton({
    super.key,
    required this.state,
    required this.onTap,
    this.size = 88,
  });

  @override
  State<VoiceInputButton> createState() => _VoiceInputButtonState();
}

class _VoiceInputButtonState extends State<VoiceInputButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  String _label(AppLocalizations t) {
    switch (widget.state) {
      case VoiceInputState.idle:
        return t.voiceInputTapToSpeak;
      case VoiceInputState.listening:
        return t.voiceInputListening;
      case VoiceInputState.processing:
        return t.voiceInputProcessing;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context);
    final listening = widget.state == VoiceInputState.listening;
    final processing = widget.state == VoiceInputState.processing;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: _pulse,
          builder: (context, child) {
            final scale = listening ? 1 + (_pulse.value * 0.12) : 1.0;
            return Stack(
              alignment: Alignment.center,
              children: [
                if (listening)
                  Transform.scale(
                    scale: scale + 0.25,
                    child: Container(
                      width: widget.size,
                      height: widget.size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.dangerMid.withValues(alpha: 0.18),
                      ),
                    ),
                  ),
                Transform.scale(scale: listening ? scale : 1.0, child: child),
              ],
            );
          },
          child: Material(
            color: listening ? AppColors.danger : AppColors.primary,
            shape: const CircleBorder(),
            elevation: 4,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: processing ? null : widget.onTap,
              child: SizedBox(
                width: widget.size,
                height: widget.size,
                child: processing
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                      )
                    : Icon(
                        listening ? Icons.stop_rounded : Icons.mic,
                        color: Colors.white,
                        size: widget.size * 0.4,
                      ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(_label(t), style: AppTypography.label, textAlign: TextAlign.center),
      ],
    );
  }
}
