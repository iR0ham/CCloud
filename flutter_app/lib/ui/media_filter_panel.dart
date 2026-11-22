import 'package:flutter/material.dart';

import '../core/media_filters.dart';
import '../core/models.dart';
import 'theme.dart';
import 'widgets.dart';

/// Opens the filter surface and returns the chosen filters, or null when the
/// user dismissed it without applying.
///
/// The ✕ applies the current selection and closes, matching the macOS
/// popover; Esc or a tap outside returns null and keeps the previous filters.
Future<MediaFilters?> showMediaFilterPanel(
  BuildContext context,
  MediaFilters current, {
  bool showKind = false,
}) {
  return showDialog<MediaFilters>(
    context: context,
    builder: (_) => _MediaFilterDialog(
      initial: current.visible(showKind: showKind),
      showKind: showKind,
    ),
  );
}

/// Filter button with an active-criterion badge.
class MediaFilterButton extends StatelessWidget {
  const MediaFilterButton({
    super.key,
    required this.filters,
    required this.onTap,
    this.showKind = false,
  });

  final MediaFilters filters;
  final VoidCallback onTap;

  /// Whether the surface offers the «همه/فیلم/سریال» section. A hidden kind
  /// cannot be set, so it must not tint the button or count in the badge.
  final bool showKind;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final displayed = filters.visible(showKind: showKind);
    return Tooltip(
      message: 'فیلتر بر اساس نوع، سال ساخت و امتیاز IMDb',
      child: AppFocusable(
        onTap: onTap,
        borderRadius: 999,
        focusScale: 1.03,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          decoration: BoxDecoration(
            color: displayed.isActive ? AppColors.accent : palette.card,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: displayed.isActive ? AppColors.accent : palette.stroke,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.tune_rounded,
                size: 17,
                color: displayed.isActive
                    ? Colors.white
                    : palette.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                'فیلتر',
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 12.5,
                  fontWeight: displayed.isActive
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: displayed.isActive
                      ? Colors.white
                      : palette.textSecondary,
                ),
              ),
              if (displayed.isActive) ...[
                const SizedBox(width: 6),
                Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  height: 18,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.24),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    faDigits(displayed.activeCount),
                    style: const TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Removable chips for every active criterion, plus «پاک کردن همه».
class ActiveMediaFilterChips extends StatelessWidget {
  const ActiveMediaFilterChips({
    super.key,
    required this.filters,
    required this.onChange,
    this.showKind = false,
  });

  final MediaFilters filters;
  final ValueChanged<MediaFilters> onChange;

  /// Mirrors the panel: without the kind section there is no kind chip.
  final bool showKind;

  @override
  Widget build(BuildContext context) {
    final displayed = filters.visible(showKind: showKind);
    if (!displayed.isActive) return const SizedBox.shrink();
    final chips = <Widget>[];
    for (final facet in MediaFilterFacet.values) {
      if (facet == MediaFilterFacet.kind && !showKind) continue;
      final label = displayed.facetLabel(facet);
      if (label == null) continue;
      chips.add(
        _ActiveFilterChip(
          label: label,
          onRemove: () => onChange(displayed.without(facet)),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ...chips,
          AppFocusable(
            onTap: () => onChange(const MediaFilters()),
            borderRadius: 999,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              child: Text(
                'پاک کردن همه',
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: context.palette.textTertiary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveFilterChip extends StatelessWidget {
  const _ActiveFilterChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'حذف این فیلتر',
      child: AppFocusable(
        onTap: onRemove,
        borderRadius: 999,
        focusScale: 1.04,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.32)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w500,
                  color: AppColors.accentBright,
                ),
              ),
              const SizedBox(width: 5),
              const Icon(
                Icons.close_rounded,
                size: 12,
                color: AppColors.accentBright,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown while the feed is being walked for matching titles.
class MediaFilterScanningView extends StatelessWidget {
  const MediaFilterScanningView({super.key});

  @override
  Widget build(BuildContext context) {
    return const LoadingView(
      message: 'در حال بررسی عناوین با فیلترهای انتخابی…',
    );
  }
}

/// Empty state for an active filter, with the optional deeper scan.
class MediaFilteredEmptyView extends StatelessWidget {
  const MediaFilteredEmptyView({
    super.key,
    required this.hasMore,
    required this.onScanMore,
    required this.onClear,
    this.scanningMore = false,
  });

  final bool hasMore;
  final VoidCallback onScanMore;
  final VoidCallback onClear;
  final bool scanningMore;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_alt_off_rounded,
              size: 40,
              color: palette.textTertiary,
            ),
            const SizedBox(height: 13),
            Text(
              'نتیجه‌ای با این فیلترها پیدا نشد',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              hasMore
                  ? 'صفحات بارگذاری‌شده خالی بودند؛ می‌توانید عناوین بیشتری را بررسی کنید یا فیلترها را ساده‌تر کنید.'
                  : 'فیلترها را تغییر دهید یا پاک کنید.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (hasMore)
                  FilledButton(
                    onPressed: scanningMore ? null : onScanMore,
                    child: scanningMore
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('بررسی عناوین بیشتر'),
                  ),
                OutlinedButton(
                  onPressed: onClear,
                  child: const Text('پاک کردن فیلترها'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaFilterDialog extends StatefulWidget {
  const _MediaFilterDialog({required this.initial, required this.showKind});

  final MediaFilters initial;
  final bool showKind;

  @override
  State<_MediaFilterDialog> createState() => _MediaFilterDialogState();
}

class _MediaFilterDialogState extends State<_MediaFilterDialog> {
  late MediaFilters _filters = widget.initial;

  static const List<double> _imdbChoices = [6, 7, 8, 9];

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final years = filterYearChoices();
    final height = MediaQuery.sizeOf(context).height;
    return Dialog(
      backgroundColor: palette.elevated,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.large),
        side: BorderSide(color: palette.stroke),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 344,
          maxHeight: (height - 48).clamp(320.0, 640.0),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'فیلترها',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _filters.isActive
                        ? () => setState(() => _filters = const MediaFilters())
                        : null,
                    child: const Text('پاک کردن همه'),
                  ),
                  IconButton(
                    tooltip: 'بستن',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(_filters),
                    icon: const Icon(Icons.close_rounded, size: 19),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              if (widget.showKind) ...[
                _label(context, 'نوع'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _ChoiceChip(
                      label: 'همه',
                      selected: _filters.kind == null,
                      onTap: () =>
                          setState(() => _filters = _filters.withKind(null)),
                    ),
                    _ChoiceChip(
                      label: 'فیلم',
                      selected: _filters.kind == MediaKind.movie,
                      onTap: () => setState(
                        () => _filters = _filters.withKind(MediaKind.movie),
                      ),
                    ),
                    _ChoiceChip(
                      label: 'سریال',
                      selected: _filters.kind == MediaKind.series,
                      onTap: () => setState(
                        () => _filters = _filters.withKind(MediaKind.series),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
              ],
              _label(context, 'سال ساخت'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _YearMenu(
                      prefix: 'از',
                      value: _filters.yearFrom,
                      years: years,
                      onChanged: (value) => setState(
                        () => _filters = _filters.withYearFrom(value),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _YearMenu(
                      prefix: 'تا',
                      value: _filters.yearTo,
                      years: years,
                      onChanged: (value) =>
                          setState(() => _filters = _filters.withYearTo(value)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'برای فیلتر یک سال مشخص، «از» و «تا» را برابر انتخاب کنید.',
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 10,
                  height: 1.6,
                  color: palette.textTertiary,
                ),
              ),
              const SizedBox(height: 18),
              _label(context, 'حداقل امتیاز IMDb'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _ChoiceChip(
                    label: 'همه',
                    selected: _filters.minIMDb == null,
                    onTap: () =>
                        setState(() => _filters = _filters.withMinImdb(null)),
                  ),
                  for (final value in _imdbChoices)
                    _ChoiceChip(
                      label: '${formatImdbThreshold(value)}+',
                      selected: _filters.minIMDb == value,
                      onTap: () => setState(
                        () => _filters = _filters.withMinImdb(
                          _filters.minIMDb == value ? null : value,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(_filters),
                      child: const Text('اعمال فیلترها'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(BuildContext context, String text) => Align(
    alignment: Alignment.centerRight,
    child: Text(
      text,
      style: TextStyle(
        fontFamily: AppTheme.fontFamily,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: context.palette.textSecondary,
      ),
    ),
  );
}

class _YearMenu extends StatelessWidget {
  const _YearMenu({
    required this.prefix,
    required this.value,
    required this.years,
    required this.onChanged,
  });

  final String prefix;
  final int? value;
  final List<int> years;
  final ValueChanged<int?> onChanged;

  static const int _none = -1;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: palette.stroke),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: value ?? _none,
          isExpanded: true,
          isDense: true,
          borderRadius: BorderRadius.circular(9),
          dropdownColor: palette.elevated,
          icon: const Icon(Icons.expand_more_rounded, size: 17),
          style: TextStyle(
            fontFamily: AppTheme.fontFamily,
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: palette.textSecondary,
          ),
          selectedItemBuilder: (context) => [
            for (final year in [null, ...years])
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  year == null ? '$prefix سال' : '$prefix $year',
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    color: year == null
                        ? palette.textSecondary
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ),
          ],
          items: [
            const DropdownMenuItem<int>(value: _none, child: Text('هر سال')),
            for (final year in years)
              DropdownMenuItem<int>(value: year, child: Text('$year')),
          ],
          onChanged: (selected) => onChanged(
            selected == null || selected == _none ? null : selected,
          ),
        ),
      ),
    );
  }
}

class _ChoiceChip extends StatelessWidget {
  const _ChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppFocusable(
      onTap: onTap,
      borderRadius: 999,
      focusScale: 1.04,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : palette.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.accent : palette.stroke,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: AppTheme.fontFamily,
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? Colors.white : palette.textSecondary,
          ),
        ),
      ),
    );
  }
}
