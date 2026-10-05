import 'package:flutter/material.dart';

import '../models/profile.dart';
import '../theme/app_theme.dart';

/// Circular gradient avatar showing the profile's emoji.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    required this.profile,
    this.size = 72,
    this.ring = false,
  });

  final Profile profile;
  final double size;

  /// Draws a soft white ring around the avatar (for use on coloured
  /// backgrounds).
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final color = Color(profile.colorValue);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color.lighten(0.08), color.darken(0.10)],
        ),
        border: ring
            ? Border.all(
                color: Colors.white.withValues(alpha: 0.85), width: size * 0.05)
            : null,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: size * 0.28,
            offset: Offset(0, size * 0.10),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        profile.emoji,
        style: TextStyle(fontSize: size * 0.48, height: 1),
      ),
    );
  }
}

/// Accent colours a parent can pick for a profile.
const List<int> kProfileColors = [
  0xFF0B7B7A, // teal
  0xFF2E86DE, // blue
  0xFF7C5CFF, // violet
  0xFFEC5FA6, // pink
  0xFFFF7A5C, // coral
  0xFFFF9838, // orange
  0xFFF5B532, // amber
  0xFF43B97F, // green
];

const List<String> kProfileEmojis = [
  '🙂', '😎', '🦄', '🐯', '🚀', '🐼', '🦊', '🐸', '🌈', '⚽', '🎮', '🎨',
  '🐱', '🐶', '🦖', '🧸', '🍓', '⭐',
];
