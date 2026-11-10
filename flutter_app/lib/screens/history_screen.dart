import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/stores.dart';
import '../ui/nav.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'detail_screen.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final history = AppServices.instance.history;
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: history,
        builder: (context, _) {
          final entries = history.entries;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('اخیراً دیده‌شده',
                              style:
                                  Theme.of(context).textTheme.headlineMedium),
                          Text(
                            '${faDigits(entries.length)} عنوان',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (entries.isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () => _confirmClear(context),
                        icon: const Icon(Icons.delete_outline_rounded,
                            size: 18),
                        label: const Text('پاک‌کردن همه'),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: entries.isEmpty
                    ? const EmptyView(
                        message:
                            'هر چیزی که تماشا کنید اینجا ثبت می‌شود تا بعداً ادامه دهید.',
                        icon: Icons.history_toggle_off_rounded,
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 30),
                        itemCount: entries.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) => _HistoryTile(
                          entry: entries[index],
                          onOpen: () => Navigator.of(context)
                              .push(appRoute(DetailScreen(
                                  item: entries[index].item))),
                          onRemove: () => history.remove(entries[index].item),
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('پاک‌کردن تاریخچه'),
        content: const Text('همهٔ موارد اخیراً دیده‌شده حذف شوند؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('پاک شود'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await AppServices.instance.history.clear();
    }
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.entry,
    required this.onOpen,
    required this.onRemove,
  });

  final HistoryEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final item = entry.item;
    final lastEpisode = entry.lastEpisode;
    final percent = (entry.progress * 100).round();

    return AppFocusable(
      onTap: onOpen,
      borderRadius: AppRadii.normal,
      focusScale: 1.01,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: context.palette.card,
          borderRadius: BorderRadius.circular(AppRadii.normal),
          border: Border.all(color: context.palette.stroke),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 54,
              height: 81,
              child: AsyncImage(
                url: item.image,
                borderRadius: BorderRadius.circular(9),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  Text(
                    _subtitle(lastEpisode),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99),
                    child: LinearProgressIndicator(
                      value: entry.progress <= 0 ? 0.02 : entry.progress,
                      minHeight: 4,
                      backgroundColor: context.palette.stroke,
                      color: AppColors.accentBright,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    percent <= 0 ? 'شروع‌نشده' : '${faDigits(percent)}٪ تماشا شده',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: context.palette.textTertiary),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onRemove,
              tooltip: 'حذف از تاریخچه',
              icon: Icon(Icons.close_rounded,
                  size: 18, color: context.palette.textTertiary),
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle(WatchedEpisode? episode) {
    if (episode == null) {
      return entry.item.isSeries ? 'سریال' : 'فیلم';
    }
    final parts = [
      if (episode.seasonTitle.isNotEmpty) episode.seasonTitle,
      if (episode.label.isNotEmpty) episode.label,
    ];
    return parts.isEmpty ? 'سریال' : parts.join(' • ');
  }
}
