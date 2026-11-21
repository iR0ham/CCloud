import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api_client.dart';
import '../core/catalogue.dart';
import '../core/downloads_store.dart';
import '../core/models.dart';
import '../core/platform_identity.dart';
import '../core/stores.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _checking = false;
  int _genreCount = 0;

  @override
  void initState() {
    super.initState();
    _genreCount = Catalogue.cachedGenres?.length ?? 0;
    _refreshGenres();
  }

  Future<void> _refreshGenres() async {
    try {
      final genres = await Catalogue.genres();
      if (!mounted) return;
      setState(() => _genreCount = genres.length);
    } catch (_) {
      // The server card already shows the connection state; a failed count
      // stays at its last value.
    }
  }

  Future<void> _checkConnection() async {
    setState(() => _checking = true);
    final ok = await ApiClient.instance.healthCheck();
    if (ok) {
      Catalogue.invalidate();
      await _refreshGenres();
    }
    if (!mounted) return;
    setState(() => _checking = false);
    _snack(
      ok
          ? 'اتصال به سرور برقرار است (${ApiClient.instance.activeHost})'
          : 'اتصال به سرور برقرار نشد',
    );
  }

  void _snack(String message) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  // MARK: Downloads

  Future<void> _reveal(DownloadItem item) async {
    final downloads = AppServices.instance.downloads;
    final opened = await downloads.reveal(item.id);
    if (opened || !mounted) return;
    // Android has no file-manager hook: hand the user the path instead.
    await Clipboard.setData(ClipboardData(text: downloads.fileFor(item).path));
    if (mounted) _snack('مسیر فایل کپی شد');
  }

  Future<void> _revealFolder() async {
    final downloads = AppServices.instance.downloads;
    final opened = await downloads.revealFolder();
    if (opened || !mounted) return;
    await Clipboard.setData(ClipboardData(text: downloads.directory.path));
    if (mounted) _snack('مسیر پوشهٔ دانلود کپی شد');
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppServices.instance.settings;
    final downloads = AppServices.instance.downloads;
    final connectivity = ApiClient.instance.connectivity;
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: Listenable.merge([settings, downloads, connectivity]),
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
                title: 'دانلودها',
                // Android has no public Downloads/CCloud path the app may
                // write to, so the card must not promise one there.
                subtitle: Platform.isAndroid
                    ? 'ذخیره در پوشهٔ دانلود حافظهٔ برنامه'
                    : 'ذخیرهٔ مستقیم در پوشهٔ Downloads/CCloud',
                children: [
                  if (downloads.items.isEmpty)
                    Text(
                      'هنوز دانلودی شروع نشده است. از صفحهٔ جزئیات فیلم یا قسمت سریال، دکمهٔ دانلود را بزنید.',
                      style: Theme.of(context).textTheme.bodySmall,
                    )
                  else
                    for (final item in downloads.items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _DownloadRow(
                          item: item,
                          onCancel: () => downloads.cancel(item.id),
                          onRetry: () => downloads.retry(item.id),
                          onReveal: () => _reveal(item),
                          onRemove: () => downloads.remove(item.id),
                        ),
                      ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: _revealFolder,
                        icon: const Icon(Icons.folder_outlined, size: 17),
                        label: const Text('نمایش پوشهٔ دانلود'),
                      ),
                      if (downloads.items.any(
                        (item) => item.state != DownloadState.downloading,
                      ))
                        TextButton.icon(
                          onPressed: downloads.clearFinished,
                          icon: const Icon(
                            Icons.playlist_remove_rounded,
                            size: 17,
                          ),
                          label: const Text('پاک کردن فهرست'),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _Section(
                title: 'وضعیت سرور',
                subtitle: 'وضعیت اتصال به بک‌اند CCloud',
                children: [
                  _InfoRow(
                    label: 'هاست فعال',
                    value: connectivity.host,
                    tint: Theme.of(context).colorScheme.onSurface,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        'وضعیت اتصال',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const Spacer(),
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: connectivity.isOffline
                              ? AppColors.gold
                              : connectivity.hasError
                              ? AppColors.red
                              : AppColors.green,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        connectivity.isOffline
                            ? 'آفلاین'
                            : connectivity.hasError
                            ? 'قطع'
                            : 'متصل',
                        style: TextStyle(
                          fontFamily: AppTheme.fontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: connectivity.isOffline
                              ? AppColors.gold
                              : connectivity.hasError
                              ? AppColors.red
                              : AppColors.green,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _InfoRow(
                    label: 'ژانرهای دریافتی',
                    value: faDigits(_genreCount),
                    tint: Theme.of(context).colorScheme.onSurface,
                  ),
                  if (connectivity.lastError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      connectivity.lastError!,
                      maxLines: 3,
                      style: TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 11,
                        color: AppColors.red,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: _checking ? null : _checkConnection,
                        icon: const Icon(
                          Icons.wifi_tethering_rounded,
                          size: 17,
                        ),
                        label: Text(
                          _checking ? 'در حال بررسی…' : 'بررسی اتصال',
                        ),
                      ),
                    ],
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
                      _snack('حافظهٔ موقت خالی شد');
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
                            PlatformIdentity.current.versionLabel,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    PlatformIdentity.current.featureBlurb,
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
    _snack('انجام شد');
  }
}

// MARK: - Download row

class _DownloadRow extends StatelessWidget {
  const _DownloadRow({
    required this.item,
    required this.onCancel,
    required this.onRetry,
    required this.onReveal,
    required this.onRemove,
  });

  final DownloadItem item;
  final VoidCallback onCancel;
  final VoidCallback onRetry;
  final VoidCallback onReveal;
  final VoidCallback onRemove;

  String get _sizeText {
    final received = _megabytes(item.receivedBytes);
    if (item.totalBytes > 0) {
      return '$received از ${_megabytes(item.totalBytes)} مگابایت';
    }
    return '$received مگابایت';
  }

  String _megabytes(int bytes) => faDigits((bytes / 1048576).round());

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: context.palette.elevated,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: context.palette.stroke),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 34,
              height: 48,
              child: AsyncImage(
                url: item.posterURL,
                placeholderIcon: Icons.arrow_downward_rounded,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                _statusLine(context),
                if (item.state == DownloadState.downloading) ...[
                  const SizedBox(height: 6),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: item.progress <= 0 ? 0.02 : item.progress,
                        minHeight: 3,
                        backgroundColor: context.palette.stroke,
                        color: AppColors.accent,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          ..._actions(),
        ],
      ),
    );
  }

  Widget _statusLine(BuildContext context) {
    switch (item.state) {
      case DownloadState.downloading:
        return Text(
          'در حال دانلود • ٪${faDigits((item.progress * 100).round())} • $_sizeText',
          style: const TextStyle(
            fontFamily: AppTheme.fontFamily,
            fontSize: 11,
            color: AppColors.accentBright,
          ),
        );
      case DownloadState.completed:
        return Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              size: 12,
              color: AppColors.green,
            ),
            const SizedBox(width: 4),
            Text(
              'دانلود شد • $_sizeText',
              style: const TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 11,
                color: AppColors.green,
              ),
            ),
          ],
        );
      case DownloadState.failed:
        return Text(
          item.errorMessage ?? 'دانلود ناموفق بود',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontFamily: AppTheme.fontFamily,
            fontSize: 11,
            color: AppColors.red,
          ),
        );
    }
  }

  List<Widget> _actions() {
    switch (item.state) {
      case DownloadState.downloading:
        return [
          IconButton(
            onPressed: onCancel,
            tooltip: 'لغو دانلود',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 18),
          ),
        ];
      case DownloadState.completed:
        return [
          IconButton(
            onPressed: onReveal,
            tooltip: 'نمایش در پوشه',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.folder_outlined, size: 18),
          ),
          IconButton(
            onPressed: onRemove,
            tooltip: 'حذف از فهرست',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
          ),
        ];
      case DownloadState.failed:
        return [
          IconButton(
            onPressed: onRetry,
            tooltip: 'تلاش دوباره',
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.refresh_rounded,
              size: 18,
              color: AppColors.accentBright,
            ),
          ),
          IconButton(
            onPressed: onRemove,
            tooltip: 'حذف از فهرست',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.delete_outline_rounded, size: 18),
          ),
        ];
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    required this.tint,
  });

  final String label;
  final String value;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.left,
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: tint,
            ),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, this.subtitle, required this.children});

  final String title;
  final String? subtitle;
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
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
          ],
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
