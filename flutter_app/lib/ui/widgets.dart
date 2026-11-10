import 'dart:math' as math;
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import 'theme.dart';

/// Clickable + D-pad focusable wrapper: Enter / SELECT activates, focus ring is visible on TV.
class AppFocusable extends StatefulWidget {
  const AppFocusable({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.borderRadius = AppRadii.normal,
    this.focusScale = 1.045,
    this.autofocus = false,
    this.focusNode,
    this.enabled = true,
    this.showHighlight = true,
    this.keepDirectionalWithinScrollable = false,
  });

  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double borderRadius;
  final double focusScale;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool enabled;
  final bool showHighlight;

  /// Vertical D-pad moves stay inside this widget's list and scroll it instead
  /// of jumping to a neighbouring column when the list edge is reached.
  final bool keepDirectionalWithinScrollable;

  @override
  State<AppFocusable> createState() => _AppFocusableState();
}

class _AppFocusableState extends State<AppFocusable> {
  FocusNode? _ownedNode;
  bool _focused = false;
  bool _hovered = false;

  FocusNode get _node => widget.focusNode ?? (_ownedNode ??= FocusNode());

  @override
  void dispose() {
    _ownedNode?.dispose();
    super.dispose();
  }

  /// Moves focus like the default D-pad policy. When no built sibling exists in
  /// that direction (lazy lists only build what is near the viewport), scrolls
  /// the enclosing list so the next item gets built and focuses it. Lists that
  /// opt in never jump to a neighbouring column when their end is reached.
  bool _moveFocus(TraversalDirection direction) {
    // `Focus.of(context)` would resolve to the ancestor above this widget; the
    // action fires for this tile's own node.
    final node = _node;
    final vertical = direction == TraversalDirection.up ||
        direction == TraversalDirection.down;
    final listScrollable = widget.keepDirectionalWithinScrollable
        ? Scrollable.maybeOf(context)
        : null;

    if (listScrollable != null && vertical) {
      if (_moveWithinList(node, listScrollable, direction)) return true;
      // The list edge was reached: Down stays put, Up goes to the control that
      // sits directly above the list (search field) instead of wandering into
      // a neighbouring column.
      if (direction == TraversalDirection.down) return true;
      _focusAboveInColumn(node)?.requestFocus();
      return true;
    }

    if (node.focusInDirection(direction)) return true;

    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) return false;
    if (!_scrollOneStep(scrollable, direction, retryNode: node)) return false;
    return true;
  }

  /// Focuses the nearest sibling inside [list] in [direction], scrolling the
  /// list one step when the sibling has not been built yet.
  bool _moveWithinList(
    FocusNode node,
    ScrollableState list,
    TraversalDirection direction,
  ) {
    final down = direction == TraversalDirection.down;
    final next = _siblingInList(node, list, down);
    if (next != null) {
      next.requestFocus();
      return true;
    }
    return _scrollOneStep(
      list,
      direction,
      onSettled: () {
        if (!mounted) return;
        _siblingInList(node, list, down)?.requestFocus();
      },
    );
  }

  FocusNode? _siblingInList(FocusNode current, ScrollableState list, bool down) {
    final currentContext = current.context;
    if (currentContext == null ||
        currentContext.findRenderObject() == null) {
      return null;
    }
    final currentRect = current.rect;
    FocusNode? best;
    var bestScore = double.infinity;
    for (final candidate in FocusScope.of(context).traversalDescendants) {
      if (candidate == current || !candidate.canRequestFocus) continue;
      final candidateContext = candidate.context;
      if (candidateContext == null ||
          candidateContext.findRenderObject() == null) {
        continue;
      }
      if (candidateContext.findAncestorStateOfType<ScrollableState>() != list) {
        continue;
      }
      final rect = candidate.rect;
      if (rect.isEmpty) continue;
      final beyond = down
          ? rect.top >= currentRect.bottom - 1
          : rect.bottom <= currentRect.top + 1;
      if (!beyond) continue;
      final overlap = math.min(rect.right, currentRect.right) -
          math.max(rect.left, currentRect.left);
      final distance = down
          ? rect.top - currentRect.bottom
          : currentRect.top - rect.bottom;
      final score = (overlap > 0 ? 0.0 : 5000.0) + distance.abs();
      if (score < bestScore) {
        bestScore = score;
        best = candidate;
      }
    }
    return best;
  }

  /// Finds the closest focusable control above [current] that shares its
  /// horizontal band (the header/search field of the same column).
  FocusNode? _focusAboveInColumn(FocusNode current) {
    final currentContext = current.context;
    if (currentContext == null ||
        currentContext.findRenderObject() == null) {
      return null;
    }
    final currentRect = current.rect;
    FocusNode? best;
    var bestScore = double.infinity;
    for (final candidate in FocusScope.of(context).traversalDescendants) {
      if (candidate == current || !candidate.canRequestFocus) continue;
      final candidateContext = candidate.context;
      if (candidateContext == null ||
          candidateContext.findRenderObject() == null) {
        continue;
      }
      final rect = candidate.rect;
      if (rect.isEmpty) continue;
      if (rect.bottom > currentRect.top + 1) continue;
      final overlap = math.min(rect.right, currentRect.right) -
          math.max(rect.left, currentRect.left);
      if (overlap <= 0) continue;
      final score = (currentRect.top - rect.bottom).abs();
      if (score < bestScore) {
        bestScore = score;
        best = candidate;
      }
    }
    return best;
  }

  bool _scrollOneStep(
    ScrollableState scrollable,
    TraversalDirection direction, {
    FocusNode? retryNode,
    VoidCallback? onSettled,
  }) {
    final position = scrollable.position;
    if (!position.hasContentDimensions) return false;
    final vertical = position.axis == Axis.vertical;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final forward = vertical
        ? direction == TraversalDirection.down
        : direction ==
            (rtl ? TraversalDirection.left : TraversalDirection.right);
    final backward = vertical
        ? direction == TraversalDirection.up
        : direction ==
            (rtl ? TraversalDirection.right : TraversalDirection.left);
    if (!forward && !backward) return false;
    const step = 140.0;
    final target = (position.pixels + (forward ? step : -step))
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    if (target == position.pixels) return false;
    position
        .animateTo(
          target,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
        )
        .then((_) {
      if (!mounted) return;
      onSettled?.call();
      if (retryNode != null && retryNode.hasFocus) {
        retryNode.focusInDirection(direction);
      }
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final highlighted = (_focused || _hovered) && widget.enabled;
    return FocusableActionDetector(
      focusNode: _node,
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      mouseCursor: SystemMouseCursors.click,
      onFocusChange: (value) {
        if (_focused != value) setState(() => _focused = value);
        if (value) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
            );
          });
        }
      },
      onShowHoverHighlight: (value) {
        if (_hovered != value) setState(() => _hovered = value);
      },
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.gameButtonA): ActivateIntent(),
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
        DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
          onInvoke: (intent) => _moveFocus(intent.direction),
        ),
      },
      child: GestureDetector(
        onTap: widget.enabled ? widget.onTap : null,
        onLongPress: widget.enabled ? widget.onLongPress : null,
        child: AnimatedScale(
          scale: highlighted ? widget.focusScale : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            decoration: widget.showHighlight
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(widget.borderRadius),
                    border: Border.all(
                      color: highlighted
                          ? AppColors.accentBright
                          : Colors.transparent,
                      width: 2,
                    ),
                    boxShadow: _focused
                        ? [
                            BoxShadow(
                              color: AppColors.accent.withValues(alpha: 0.35),
                              blurRadius: 22,
                              spreadRadius: 1,
                            ),
                          ]
                        : null,
                  )
                : null,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Lets the D-pad leave a single-line text field with Up/Down; otherwise the
/// editing shortcuts swallow those keys for vertical caret movement.
class DpadTextField extends StatefulWidget {
  const DpadTextField({super.key, required this.child});

  final Widget child;

  @override
  State<DpadTextField> createState() => _DpadTextFieldState();
}

class _DpadTextFieldState extends State<DpadTextField> {
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final direction = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowUp => TraversalDirection.up,
      LogicalKeyboardKey.arrowDown => TraversalDirection.down,
      _ => null,
    };
    if (direction == null) return KeyEventResult.ignored;
    // Always consume: letting the event fall through to the app's default
    // directional traversal jumps into a neighbouring column.
    _moveOut(direction);
    return KeyEventResult.handled;
  }

  /// Focuses the nearest focusable control outside this field, in the same
  /// horizontal band, in [direction].
  bool _moveOut(TraversalDirection direction) =>
      focusNearestOutsideColumn(context, direction);

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKeyEvent,
      child: widget.child,
    );
  }
}

/// Focuses the nearest focusable control outside [context]'s widget, in the
/// same horizontal band, in [direction]. Used by text fields so the D-pad
/// keeps moving instead of trapping focus inside the field.
bool focusNearestOutsideColumn(
    BuildContext context, TraversalDirection direction) {
  final render = context.findRenderObject();
  if (render is! RenderBox || !render.hasSize) return false;
  final rect = render.localToGlobal(Offset.zero) & render.size;
  final down = direction == TraversalDirection.down;
  FocusNode? best;
  var bestScore = double.infinity;
  for (final candidate in FocusScope.of(context).traversalDescendants) {
    if (!candidate.canRequestFocus) continue;
    final candidateContext = candidate.context;
    if (candidateContext == null ||
        candidateContext.findRenderObject() == null) {
      continue;
    }
    final other = candidate.rect;
    if (other.isEmpty) continue;
    final beyond =
        down ? other.top >= rect.bottom - 1 : other.bottom <= rect.top + 1;
    if (!beyond) continue;
    final overlap =
        math.min(other.right, rect.right) - math.max(other.left, rect.left);
    if (overlap <= 0) continue;
    final distance = down ? other.top - rect.bottom : rect.top - other.bottom;
    if (distance < bestScore) {
      bestScore = distance;
      best = candidate;
    }
  }
  if (best == null) return false;
  best.requestFocus();
  return true;
}

/// Search field for remote-controlled screens. The soft keyboard only opens
/// after Select (or a tap), so a focused field never traps the D-pad.
class TvSearchField extends StatefulWidget {
  const TvSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.icon,
    this.onChanged,
    this.style,
    this.iconSize,
    this.isDense = true,
    this.contentPadding,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final ValueChanged<String>? onChanged;
  final TextStyle? style;
  final double? iconSize;
  final bool isDense;
  final EdgeInsetsGeometry? contentPadding;

  @override
  State<TvSearchField> createState() => _TvSearchFieldState();
}

class _TvSearchFieldState extends State<TvSearchField> {
  late final FocusNode _node = FocusNode(debugLabel: 'tv-search')
    ..addListener(_onFocusChange);
  bool _editing = false;

  void _onFocusChange() {
    if (!_node.hasFocus && _editing) {
      setState(() => _editing = false);
    }
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  void _startEditing() {
    if (_editing) return;
    setState(() => _editing = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _node.requestFocus();
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    });
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (!_editing &&
        (key == LogicalKeyboardKey.select ||
            key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.space ||
            key == LogicalKeyboardKey.gameButtonA)) {
      _startEditing();
      return KeyEventResult.handled;
    }
    final direction = switch (key) {
      LogicalKeyboardKey.arrowUp => TraversalDirection.up,
      LogicalKeyboardKey.arrowDown => TraversalDirection.down,
      _ => null,
    };
    if (direction == null) return KeyEventResult.ignored;
    // With the keyboard open the IME consumes these first; otherwise leave.
    if (_editing) setState(() => _editing = false);
    focusNearestOutsideColumn(context, direction);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onKeyEvent,
      child: TextField(
        controller: widget.controller,
        focusNode: _node,
        readOnly: !_editing,
        onTap: _startEditing,
        onChanged: widget.onChanged,
        style: widget.style,
        decoration: InputDecoration(
          hintText: widget.hintText,
          prefixIcon: Icon(widget.icon, size: widget.iconSize),
          isDense: widget.isDense,
          contentPadding: widget.contentPadding,
        ),
      ),
    );
  }
}

class AsyncImage extends StatelessWidget {
  const AsyncImage({
    super.key,
    required this.url,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.placeholderIcon = Icons.image_outlined,
  });

  final String? url;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final IconData placeholderIcon;

  @override
  Widget build(BuildContext context) {
    final resolved = url == null ? null : ApiClient.instance.imageUrl(url!);
    final palette = context.palette;
    final child = resolved == null
        ? _placeholder(palette)
        : CachedNetworkImage(
            imageUrl: resolved,
            fit: fit,
            fadeInDuration: const Duration(milliseconds: 220),
            placeholder: (context, _) => Container(
              color: palette.card,
              alignment: Alignment.center,
              child: const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            errorWidget: (context, _, _) => _placeholder(palette),
          );
    if (borderRadius == null) return child;
    return ClipRRect(borderRadius: borderRadius!, child: child);
  }

  Widget _placeholder(AppPalette palette) => Container(
        color: palette.card,
        alignment: Alignment.center,
        child: Icon(placeholderIcon, color: palette.textTertiary, size: 28),
      );
}

class RatingBadge extends StatelessWidget {
  const RatingBadge({super.key, required this.imdb, this.compact = false});

  final double imdb;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (imdb <= 0) return const SizedBox.shrink();
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.star_rounded, color: AppColors.gold, size: 15),
          const SizedBox(width: 3),
          Text(
            imdb.toStringAsFixed(1),
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              color: Colors.white,
              fontSize: compact ? 10.5 : 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

const double _posterCaptionFontSize = 12.5;
const double _posterCaptionLineHeight = 1.3;
const double _posterCaptionGap = 8;
const double _railPadding = 4;

class MediaPosterCard extends StatelessWidget {
  const MediaPosterCard({
    super.key,
    required this.item,
    required this.onTap,
    this.width = 156,
    this.autofocus = false,
    this.focusNode,
    this.showTitle = true,
  });

  final MediaItem item;
  final VoidCallback onTap;
  final double width;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool showTitle;

  /// Natural height of a card at [width]: the 2:3 poster plus its caption.
  /// The caption line box is pinned by its style so fixed-height parents can
  /// size themselves from this value without overflowing.
  static double heightForWidth(double width) =>
      width * 1.5 +
      _posterCaptionGap +
      _posterCaptionFontSize * _posterCaptionLineHeight;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final posterUrl = ApiClient.instance.imageUrl(item.image);
    return SizedBox(
      width: width,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppFocusable(
            onTap: onTap,
            autofocus: autofocus,
            focusNode: focusNode,
            borderRadius: AppRadii.normal,
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AsyncImage(
                    url: posterUrl,
                    borderRadius: BorderRadius.circular(AppRadii.normal),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: RatingBadge(imdb: item.imdb, compact: true),
                  ),
                  if (item.isSeries)
                    Positioned(
                      bottom: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.92),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'سریال',
                          style: TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (showTitle) ...[
            const SizedBox(height: _posterCaptionGap),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: _posterCaptionFontSize,
                height: _posterCaptionLineHeight,
                fontWeight: FontWeight.w500,
                color: palette.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = context.palette;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleLarge),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          AppFocusable(
            onTap: onAction!,
            borderRadius: 999,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    actionLabel!,
                    style: TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.accentBright,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.chevron_left_rounded,
                    size: 18,
                    color: palette.textSecondary,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class MediaRail extends StatelessWidget {
  const MediaRail({
    super.key,
    required this.title,
    required this.items,
    required this.onOpen,
    this.subtitle,
    this.onSeeAll,
    this.cardWidth = 156,
    this.firstFocusNode,
  });

  final String title;
  final String? subtitle;
  final List<MediaItem> items;
  final void Function(MediaItem item) onOpen;
  final VoidCallback? onSeeAll;
  final double cardWidth;
  final FocusNode? firstFocusNode;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(
          title: title,
          subtitle: subtitle,
          actionLabel: onSeeAll == null ? null : 'همه',
          onAction: onSeeAll,
        ),
        const SizedBox(height: 12),
        SizedBox(
          // Focus-ring breathing room above and below the cards; without it
          // the list's tight cross axis clips the caption's last pixels.
          height: MediaPosterCard.heightForWidth(cardWidth) + 2 * _railPadding,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            padding: const EdgeInsets.symmetric(
              vertical: _railPadding,
              horizontal: 2,
            ),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) => MediaPosterCard(
              item: items[index],
              width: cardWidth,
              onTap: () => onOpen(items[index]),
              focusNode: index == 0 ? firstFocusNode : null,
            ),
          ),
        ),
      ],
    );
  }
}

class FilterPills extends StatelessWidget {
  const FilterPills({
    super.key,
    required this.values,
    required this.selected,
    required this.labelBuilder,
    required this.onSelected,
  });

  final List<int> values;
  final int selected;
  final String Function(int value) labelBuilder;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final value = values[index];
          final isSelected = value == selected;
          return AppFocusable(
            onTap: () => onSelected(value),
            borderRadius: 999,
            focusScale: 1.03,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.accent
                    : context.palette.card,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: isSelected
                      ? AppColors.accent
                      : context.palette.stroke,
                ),
              ),
              child: Text(
                labelBuilder(value),
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? Colors.white
                      : context.palette.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          if (message != null) ...[
            const SizedBox(height: 14),
            Text(message!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.wifi_off_rounded,
                  color: AppColors.red, size: 26),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onRetry,
                child: const Text('تلاش دوباره'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
  });

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: palette.textTertiary),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Width-adaptive grid for posters.
class PosterGrid extends StatelessWidget {
  const PosterGrid({
    super.key,
    required this.items,
    required this.onOpen,
    this.maxExtent = 170,
    this.padding = const EdgeInsets.fromLTRB(16, 8, 16, 90),
    this.firstFocusNode,
  });

  final List<MediaItem> items;
  final void Function(MediaItem item) onOpen;
  final double maxExtent;
  final EdgeInsets padding;
  final FocusNode? firstFocusNode;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: padding,
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxExtent,
        mainAxisSpacing: 16,
        crossAxisSpacing: 12,
        childAspectRatio: 0.58,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => MediaPosterCard(
        item: items[index],
        width: double.infinity,
        onTap: () => onOpen(items[index]),
        focusNode: index == 0 ? firstFocusNode : null,
      ),
    );
  }
}

class MetaChip extends StatelessWidget {
  const MetaChip({super.key, required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: context.palette.card,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: context.palette.stroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: context.palette.textTertiary),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: AppTheme.fontFamily,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: context.palette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Simple blurred backdrop used behind hero elements.
class BlurredImageBackground extends StatelessWidget {
  const BlurredImageBackground({super.key, required this.url, this.opacity = 0.45});

  final String? url;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    if (url == null) return const SizedBox.shrink();
    return Stack(
      fit: StackFit.expand,
      children: [
        AsyncImage(url: url),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(color: Colors.black.withValues(alpha: opacity)),
        ),
      ],
    );
  }
}
