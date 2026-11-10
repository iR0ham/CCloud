import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../core/stores.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _host = ApiClient.instance.activeHost;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    ApiClient.instance.addHostListener((host) {
      if (mounted) setState(() => _host = host);
    });
  }

  Future<void> _checkConnection() async {
    setState(() => _checking = true);
    final ok = await ApiClient.instance.healthCheck();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _host = ApiClient.instance.activeHost;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'اتصال به سرور برقرار است ($_host)' : 'اتصال به سرور برقرار نشد',
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppServices.instance.settings;
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 34),
            children: [
              Text(
                'تنظیمات',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'ظاهر، پخش و محتوا',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 18),
              _Section(
                title: 'ظاهر',
                children: [
                  _SettingLabel(
                    title: 'حالت نمایش',
                    subtitle: 'تیره، روشن یا هماهنگ با سیستم',
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final appearance in AppAppearance.values)
                        _PillButton(
                          label: appearance.title,
                          selected: settings.appearance == appearance,
                          onTap: () => settings.setAppearance(appearance),
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _SettingLabel(
                          title: 'اندازهٔ متن',
                          subtitle:
                              '${faDigits((settings.fontScale * 100).round())}٪ اندازهٔ عادی',
                        ),
                      ),
                      Text(
                        'نمونه متن',
                        style: TextStyle(
                          fontFamily: AppTheme.fontFamily,
                          fontSize: 13 * settings.fontScale,
                          color: context.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: settings.fontScale,
                    min: 0.85,
                    max: 1.3,
                    divisions: 9,
                    onChanged: (value) => settings.setFontScale(value),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _Section(
                title: 'پخش',
                children: [
                  _SettingLabel(
                    title: 'کیفیت ترجیحی',
                    subtitle: 'در صورت نبود کیفیت انتخابی، نزدیک‌ترین کیفیت پخش می‌شود',
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (value, title) in AppSettings.qualityOptions)
                        _PillButton(
                          label: title,
                          selected: settings.preferredQuality == value,
                          onTap: () => settings.setPreferredQuality(value),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('انتخاب خودکار بهترین منبع'),
                    subtitle: const Text(
                      'اگر کیفیت انتخابی موجود نباشد، بهترین منبع انتخاب شود',
                    ),
                    value: settings.autoPlayBest,
                    onChanged: settings.setAutoPlayBest,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('پخش خودکار قسمت بعد'),
                    subtitle: const Text(
                      'پس از پایان قسمت، ۱۰ ثانیه فرصت برای ادامه یا لغو',
                    ),
                    value: settings.autoPlayNextEpisode,
                    onChanged: settings.setAutoPlayNextEpisode,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _Section(
                title: 'محتوا',
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'پنهان‌کردن محتوای شرق و جنوب آسیا و عرب',
                    ),
                    subtitle: const Text(
                      'فقط در صفحه‌های فیلم‌ها و سریال‌ها اعمال می‌شود',
                    ),
                    value: settings.hideRegionalOrigins,
                    onChanged: settings.setHideRegionalOrigins,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('پنهان‌کردن انیمه'),
                    subtitle: const Text(
                      'انیمیشن ژاپنی از فهرست فیلم‌ها و سریال‌ها حذف می‌شود',
                    ),
                    value: settings.hideAnime,
                    onChanged: settings.setHideAnime,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _Section(
                title: 'داده‌ها',
                children: [
                  _ActionRow(
                    icon: Icons.favorite_border_rounded,
                    title: 'پاک‌کردن علاقه‌مندی‌ها',
                    onTap: () => _confirm(
                      title: 'پاک‌کردن علاقه‌مندی‌ها',
                      message: 'همهٔ عنوان‌های ذخیره‌شده حذف شوند؟',
                      action: AppServices.instance.favorites.clear,
                    ),
                  ),
                  const Divider(height: 18),
                  _ActionRow(
                    icon: Icons.history_rounded,
                    title: 'پاک‌کردن تاریخچه',
                    onTap: () => _confirm(
                      title: 'پاک‌کردن تاریخچه',
                      message: 'همهٔ موارد اخیراً دیده‌شده حذف شوند؟',
                      action: AppServices.instance.history.clear,
                    ),
                  ),
                  const Divider(height: 18),
                  _ActionRow(
                    icon: Icons.cleaning_services_outlined,
                    title: 'خالی‌کردن حافظهٔ موقت',
                    onTap: () {
                      ApiClient.instance.invalidateCache();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('حافظهٔ موقت خالی شد')),
                      );
                    },
                  ),
                  const Divider(height: 18),
                  _ActionRow(
                    icon: Icons.restart_alt_rounded,
                    title: 'بازنشانی تنظیمات',
                    onTap: () => _confirm(
                      title: 'بازنشانی تنظیمات',
                      message: 'همهٔ تنظیمات به حالت پیش‌فرض برگردند؟',
                      action: settings.reset,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _Section(
                title: 'درباره',
                children: [
                  Row(
                    children: [
                      Image.asset(
                        context.isDark
                            ? 'assets/logo-dark.png'
                            : 'assets/logo.png',
                        width: 46,
                        height: 46,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.cloud_rounded,
                          color: AppColors.accent,
                          size: 42,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CCloud',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            'نسخهٔ اندروید • ۱.۰.۵',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Icon(
                        Icons.dns_rounded,
                        size: 17,
                        color: context.palette.textTertiary,
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          'سرور فعال: $_host',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      OutlinedButton(
                        onPressed: _checking ? null : _checkConnection,
                        child: Text(
                          _checking ? 'در حال بررسی…' : 'بررسی اتصال',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'رابط کاربری فارسی و راست‌به‌چپ، بهینه برای گوشی، تبلت و تلویزیون اندروید.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirm({
    required String title,
    required String message,
    required Future<void> Function() action,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('تأیید'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await action();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('انجام شد')));
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(AppRadii.large),
        border: Border.all(color: context.palette.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

class _SettingLabel extends StatelessWidget {
  const _SettingLabel({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.bodyLarge),
        if (subtitle != null)
          Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppFocusable(
      onTap: onTap,
      borderRadius: 999,
      focusScale: 1.03,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.accent : context.palette.stroke,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppTheme.fontFamily,
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? Colors.white : context.palette.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppFocusable(
      onTap: onTap,
      borderRadius: 10,
      focusScale: 1.01,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 19, color: context.palette.textSecondary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.bodyLarge),
            ),
            Icon(
              Icons.chevron_left_rounded,
              size: 18,
              color: context.palette.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
