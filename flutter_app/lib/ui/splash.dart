import 'package:flutter/material.dart';

import '../core/platform_identity.dart';
import 'theme.dart';

/// Full-screen launch overlay, mirroring the macOS `SplashView`: brand, tagline,
/// spinner, and the OS-accurate version line.
class SplashView extends StatelessWidget {
  const SplashView({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _glow(
            alignment: const Alignment(0.82, -0.85),
            color: AppColors.accent,
            size: 330,
          ),
          _glow(
            alignment: const Alignment(-0.9, 0.4),
            color: AppColors.accentBright,
            size: 270,
          ),
          SafeArea(
            child: Column(
              children: [
                const Spacer(flex: 5),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 190,
                      height: 190,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            AppColors.accent.withValues(alpha: 0.3),
                            AppColors.accent.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                    Image.asset(
                      context.isDark
                          ? 'assets/logo-dark.png'
                          : 'assets/logo.png',
                      width: 96,
                      height: 96,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.cloud_rounded,
                        color: AppColors.accent,
                        size: 88,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'CCloud',
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface,
                    shadows: [
                      Shadow(
                        color: AppColors.accent.withValues(alpha: 0.35),
                        blurRadius: 18,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'پخش رایگان فیلم و سریال',
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: palette.textSecondary,
                  ),
                ),
                const SizedBox(height: 26),
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: AppColors.accentSoft,
                  ),
                ),
                const Spacer(flex: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Text(
                    PlatformIdentity.current.versionLabel,
                    style: TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: palette.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _glow({
    required Alignment alignment,
    required Color color,
    required double size,
  }) {
    return Align(
      alignment: alignment,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: 0.32),
                color.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
