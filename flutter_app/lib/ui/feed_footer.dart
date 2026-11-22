import 'package:flutter/material.dart';

import '../core/media_filters.dart';
import '../core/models.dart';
import 'theme.dart';
import 'widgets.dart';

/// Strip below a poster grid: loading, «بررسی عناوین بیشتر», or the end caption.
///
/// Mirrors `BrowseFeedFooter` in `Sources/UI/Browse/BrowseSupport.swift`.
class BrowseFeedFooter extends StatelessWidget {
  const BrowseFeedFooter({
    super.key,
    required this.loadingMore,
    required this.filterScanning,
    required this.filterActive,
    required this.hasMore,
    required this.itemCount,
    this.onScanMore,
  });

  final bool loadingMore;
  final bool filterScanning;

  /// True when filters or content hiding narrow the feed.
  final bool filterActive;
  final bool hasMore;
  final int itemCount;
  final VoidCallback? onScanMore;

  @override
  Widget build(BuildContext context) {
    final mode = feedFooterMode(
      loadingMore: loadingMore,
      filterScanning: filterScanning,
      postFiltering: filterActive,
      hasMore: hasMore,
      itemCount: itemCount,
      canScanMore: onScanMore != null,
    );
    return SizedBox(
      height: 46,
      child: Center(
        child: switch (mode) {
          FeedFooterMode.hidden => const SizedBox.shrink(),
          FeedFooterMode.loading => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 9),
              Text(
                filterActive
                    ? 'در حال بررسی عناوین بیشتر…'
                    : 'در حال بارگذاری عنوان‌های بیشتر…',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          FeedFooterMode.scanMore => Tooltip(
            message: 'صفحات بعدی را برای یافتن نتایج بیشتر بررسی کن',
            child: AppFocusable(
              onTap: onScanMore!,
              borderRadius: 999,
              focusScale: 1.03,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.3),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.arrow_downward_rounded,
                      size: 13,
                      color: AppColors.accentBright,
                    ),
                    SizedBox(width: 7),
                    Text(
                      'بررسی عناوین بیشتر',
                      style: TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: AppColors.accentBright,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          FeedFooterMode.end => Text(
            filterActive
                ? 'پایان عناوین بررسی‌شده • ${faDigits(itemCount)} نتیجه'
                : 'پایان فهرست • ${faDigits(itemCount)} عنوان',
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 11,
              color: context.palette.textTertiary,
            ),
          ),
        },
      ),
    );
  }
}
