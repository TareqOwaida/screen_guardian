import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Full-screen numeric PIN pad.
///
/// [onSubmit] receives the entered PIN and returns `true` when it is accepted;
/// the screen then pops with the PIN. Returning `false` shakes and clears.
class PinScreen extends StatefulWidget {
  const PinScreen({
    super.key,
    required this.title,
    this.subtitle,
    required this.onSubmit,
    this.length = 4,
    this.canCancel = true,
    this.accent,
  });

  final String title;
  final String? subtitle;
  final Future<bool> Function(String pin) onSubmit;
  final int length;
  final bool canCancel;
  final Color? accent;

  /// Ask the user for a *new* PIN twice and return it (null if cancelled).
  static Future<String?> collectNewPin(
    BuildContext context, {
    String title = 'Choose a PIN',
  }) async {
    final first = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PinScreen(
          title: title,
          subtitle: 'Choose a 4-digit PIN',
          onSubmit: (_) async => true,
        ),
      ),
    );
    if (first == null || !context.mounted) return null;
    final second = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PinScreen(
          title: 'Confirm PIN',
          subtitle: 'Enter the same PIN again',
          onSubmit: (pin) async => pin == first,
        ),
      ),
    );
    return second;
  }

  /// Verify the parent (admin) PIN. Returns `true` when correct.
  static Future<bool> verifyAdmin(
    BuildContext context,
    AppState state, {
    String reason = 'Parent access required',
  }) async {
    return await requestAdminPin(context, state, reason: reason) != null;
  }

  static Future<String?> requestAdminPin(
    BuildContext context,
    AppState state, {
    String reason = 'Parent access required',
  }) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PinScreen(
          title: 'Parent PIN',
          subtitle: reason,
          onSubmit: (pin) async => state.verifyAdminPin(pin),
        ),
      ),
    );
  }

  @override
  State<PinScreen> createState() => _PinScreenState();
}

class _PinScreenState extends State<PinScreen>
    with SingleTickerProviderStateMixin {
  String _entered = '';
  bool _busy = false;
  bool _error = false;
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  Future<void> _press(String digit) async {
    if (_busy || _entered.length >= widget.length) return;
    HapticFeedback.selectionClick();
    setState(() {
      _entered += digit;
      _error = false;
    });
    if (_entered.length == widget.length) {
      setState(() => _busy = true);
      final ok = await widget.onSubmit(_entered);
      if (!mounted) return;
      if (ok) {
        Navigator.of(context).pop(_entered);
      } else {
        HapticFeedback.heavyImpact();
        _shake.forward(from: 0);
        setState(() {
          _error = true;
          _entered = '';
          _busy = false;
        });
      }
    }
  }

  void _backspace() {
    if (_entered.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    final accent = widget.accent ?? scheme.primary;
    return PopScope(
      canPop: widget.canCancel,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: widget.canCancel
              ? IconButton(
                  tooltip: 'Cancel',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).maybePop(),
                )
              : null,
        ),
        body: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              IconBubble(
                icon: Icons.lock_rounded,
                color: accent,
                size: 76,
                circular: true,
              ),
              const SizedBox(height: 20),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: context.text.headlineMedium,
              ),
              if (widget.subtitle != null) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    widget.subtitle!,
                    textAlign: TextAlign.center,
                    style: context.text.bodyLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 32),
              AnimatedBuilder(
                animation: _shake,
                builder: (context, child) {
                  final t = _shake.value;
                  final dx = t == 0
                      ? 0.0
                      : (14 * (1 - t) * ((t * 20).floor().isEven ? 1 : -1));
                  return Transform.translate(
                    offset: Offset(dx, 0),
                    child: child,
                  );
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(widget.length, (i) {
                    final filled = i < _entered.length;
                    final c = _error ? scheme.error : accent;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      curve: Curves.easeOut,
                      margin: const EdgeInsets.symmetric(horizontal: 9),
                      width: filled ? 20 : 16,
                      height: filled ? 20 : 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: (filled || _error) ? c : Colors.transparent,
                        border: Border.all(color: c, width: 2),
                      ),
                    );
                  }),
                ),
              ),
              SizedBox(
                height: 28,
                child: _error
                    ? Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          'Incorrect PIN, try again',
                          style: context.text.labelLarge?.copyWith(
                            color: scheme.error,
                          ),
                        ),
                      )
                    : null,
              ),
              const Spacer(),
              _Keypad(onDigit: _press, onBackspace: _backspace, accent: accent),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.onDigit,
    required this.onBackspace,
    required this.accent,
  });
  final void Function(String) onDigit;
  final VoidCallback onBackspace;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;

    Widget key(String label, {VoidCallback? onTap, IconData? icon}) {
      return Padding(
        padding: const EdgeInsets.all(6),
        child: Material(
          color: icon != null ? Colors.transparent : context.guardian.card,
          shape: CircleBorder(
            side: icon != null
                ? BorderSide.none
                : BorderSide(color: context.guardian.cardBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap ?? () => onDigit(label),
            child: SizedBox(
              width: 76,
              height: 76,
              child: Center(
                child: icon != null
                    ? Icon(icon, size: 28, color: scheme.onSurfaceVariant)
                    : Text(
                        label,
                        style: context.text.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: row.map(key).toList(),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(width: 88, height: 88),
            key('0'),
            key('', icon: Icons.backspace_rounded, onTap: onBackspace),
          ],
        ),
      ],
    );
  }
}
