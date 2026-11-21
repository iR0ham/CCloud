import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/platform_identity.dart';
import 'theme.dart';
import 'widgets.dart';

/// About surface shared by the side rail and Settings, mirroring the macOS
/// `AboutView` sheet: brand, platform-accurate version, description, links and
/// a persistent footer.
Future<void> showAboutSheet(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black54,
    builder: (_) => const AboutSheet(),
  );
}

class AboutSheet extends StatelessWidget {
  const AboutSheet({super.key});

  static const _githubUrl = 'https://github.com/code3-dev/CCloud';
  static const _developerUrl = 'https://t.me/h3dev';
  static const _channelUrl = 'https://t.me/irdevs_dns';

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final size = MediaQuery.sizeOf(context);
    final width = size.width < 560 ? size.width - 32 : 560.0;
    final height = size.height < 760 ? size.height - 48 : 700.0;
    final identity = PlatformIdentity.current;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: SizedBox(
          width: width,
          height: height,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 24, 28, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _Header(identity: identity),
                      const SizedBox(height: 20),
                      _Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'درباره این نسخه',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'CCloud یک برنامه رایگان برای تماشای فیلم و سریال '
                              'با دوبله و زیرنویس فارسی است. ${identity.featureBlurb}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(height: 1.9),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _Card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.link_rounded,
                                  size: 16,
                                  color: AppColors.accentBright,
                                ),
                                const SizedBox(width: 7),
                                Text(
                                  'پیوندها و اعتبار',
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            _LinkRow(
                              icon: Icons.code_rounded,
                              title: 'مخزن GitHub پروژه',
                              detail: 'github.com/code3-dev/CCloud',
                              onTap: () => _open(context, _githubUrl),
                            ),
                            Divider(color: palette.stroke, height: 17),
                            _LinkRow(
                              icon: Icons.send_rounded,
                              title: 'تلگرام توسعه‌دهنده',
                              detail: '@h3dev',
                              onTap: () => _open(context, _developerUrl),
                            ),
                            Divider(color: palette.stroke, height: 17),
                            _LinkRow(
                              icon: Icons.campaign_rounded,
                              title: 'کانال تلگرام',
                              detail: '@irdevs_dns',
                              onTap: () => _open(context, _channelUrl),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'سازنده اصلی اپلیکیشن اندروید: حسین پیرا (Hossein Pira)',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: palette.stroke),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'این برنامه برای کاربران ایرانی ساخته شده است • بدون نیاز به ثبت‌نام',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('بستن'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _open(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final uri = Uri.tryParse(url);
    var opened = false;
    if (uri != null) {
      try {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        opened = false;
      }
    }
    if (!opened && messenger != null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('باز کردن پیوند ناموفق بود')),
      );
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.identity});

  final PlatformIdentity identity;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 124,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.accent.withValues(alpha: 0.4),
                      AppColors.accent.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
              Image.asset(
                context.isDark ? 'assets/logo-dark.png' : 'assets/logo.png',
                width: 82,
                height: 82,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.cloud_rounded,
                  size: 76,
                  color: AppColors.accent,
                ),
              ),
            ],
          ),
        ),
        Text(
          'CCloud',
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 3),
        Text(
          identity.versionLabel,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),
        const Wrap(
          alignment: WrapAlignment.center,
          spacing: 7,
          runSpacing: 6,
          children: [
            _TechChip('Flutter'),
            _TechChip('Dart'),
            _TechChip('media_kit'),
          ],
        ),
      ],
    );
  }
}

class _TechChip extends StatelessWidget {
  const _TechChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: AppTheme.fontFamily,
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: AppColors.accentSoft,
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(AppRadii.normal),
        border: Border.all(color: palette.stroke),
      ),
      child: child,
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppFocusable(
      onTap: onTap,
      borderRadius: AppRadii.small,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          children: [
            Icon(icon, size: 16, color: palette.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.bodyMedium),
                  Text(
                    detail,
                    textDirection: TextDirection.ltr,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_outward_rounded,
              size: 13,
              color: palette.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
