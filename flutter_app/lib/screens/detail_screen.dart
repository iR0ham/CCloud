import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/description_text.dart';
import '../core/models.dart';
import '../core/origin_filter.dart';
import '../core/playback.dart';
import '../core/platform_info.dart';
import '../core/stores.dart';
import '../ui/nav.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'player_screen.dart';

class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key, required this.item});

  final MediaItem item;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late Future<List<Season>>? _seasons;
  late Future<List<MediaItem>> _similar;
  int _selectedSeason = 0;
  bool _descriptionExpanded = false;

  @override
  void initState() {
    super.initState();
    if (widget.item.isSeries) {
      _seasons = ApiClient.instance.seasons(widget.item.id);
    }
    _similar = _loadSimilar();
  }

  Future<List<MediaItem>> _loadSimilar() async {
    final item = widget.item;
    if (item.genres.isEmpty) return const [];
    final api = ApiClient.instance;
    final genreId = item.genres.first.id;
    try {
      final pages = await Future.wait([
        item.isSeries
            ? api.series(page: 0, genreId: genreId)
            : api.movies(page: 0, genreId: genreId),
        item.isSeries
            ? api.series(page: 1, genreId: genreId)
            : api.movies(page: 1, genreId: genreId),
      ]);
      final settings = AppServices.instance.settings;
      final seen = <int>{item.id};
      final result = <MediaItem>[];
      for (final page in pages) {
        for (final candidate in page) {
          if (result.length >= 14) break;
          if (!seen.add(candidate.id)) continue;
          if (settings.hideRegionalOrigins && OriginFilter.hides(candidate)) {
            continue;
          }
          if (settings.hideAnime && OriginFilter.hidesAnime(candidate)) {
            continue;
          }
          result.add(candidate);
        }
      }
      return result;
    } catch (_) {
      return const [];
    }
  }

  void _reloadSeasons() {
    setState(() {
      _seasons = ApiClient.instance.seasons(widget.item.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final size = MediaQuery.sizeOf(context);
    final wide = PlatformInfo.isTv || size.width >= 760;
    final side = wide ? 24.0 : 12.0;
    final bodySide = wide ? 26.0 : 18.0;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(side, wide ? 18 : 10, side, 0),
                    child: _hero(item, wide),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(bodySide, 18, bodySide, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _actions(item),
                        if (item.hasOnlyTrailer) ...[
                          const SizedBox(height: 10),
                          Text(
                            'برای این عنوان فعلاً فقط تیزر موجود است.',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppColors.gold),
                          ),
                        ],
                        const SizedBox(height: 26),
                        _storySection(item),
                        const SizedBox(height: 26),
                        if (item.isSeries)
                          _seriesSection()
                        else
                          _sourcesSection(item.playableSources),
                        if (item.genres.isNotEmpty) ...[
                          const SizedBox(height: 30),
                          _similarSection(item),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // MARK: Hero

  Widget _hero(MediaItem item, bool wide) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final textColor = Theme.of(context).colorScheme.onSurface;
    final cover = item.cover.isNotEmpty ? item.cover : item.image;
    final height = wide ? 336.0 : 300.0;
    final posterWidth = wide ? 132.0 : 106.0;
    final meta = _metaItems(item);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.large),
      child: SizedBox(
        height: height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            AsyncImage(url: cover, placeholderIcon: Icons.movie_rounded),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.10),
                    bg.withValues(alpha: 0.55),
                    bg,
                  ],
                  stops: const [0, 0.62, 1],
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                wide ? 24 : 14,
                56,
                wide ? 24 : 14,
                wide ? 20 : 14,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _poster(item, posterWidth),
                  SizedBox(width: wide ? 20 : 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: wide ? 30 : 21,
                            fontWeight: FontWeight.w800,
                            height: 1.3,
                            color: textColor,
                            shadows: [
                              Shadow(
                                color: Colors.black.withValues(alpha: 0.35),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                        ),
                        if (meta.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Wrap(spacing: 12, runSpacing: 5, children: meta),
                        ],
                        if (item.genres.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final genre in item.genres.take(
                                wide ? 6 : 3,
                              ))
                                _genreChip(genre.title),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Row(
                children: [
                  _circleButton(
                    icon: Icons.arrow_forward_rounded,
                    tooltip: 'بازگشت',
                    autofocus: PlatformInfo.isTv,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const Spacer(),
                  ListenableBuilder(
                    listenable: AppServices.instance.favorites,
                    builder: (context, _) {
                      final isFavorite = AppServices.instance.favorites
                          .isFavorite(item);
                      return _circleButton(
                        icon: isFavorite
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        iconColor: isFavorite ? AppColors.red : Colors.white,
                        tooltip: isFavorite
                            ? 'حذف از علاقه‌مندی‌ها'
                            : 'افزودن به علاقه‌مندی‌ها',
                        onTap: () => _toggleFavorite(item),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _poster(MediaItem item, double width) {
    return Container(
      width: width,
      height: width * 1.5,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: AsyncImage(url: item.image),
      ),
    );
  }

  List<Widget> _metaItems(MediaItem item) {
    final palette = context.palette;
    final duration = item.durationText;
    final hasDuration =
        duration != null &&
        duration.toUpperCase() != 'N/A' &&
        duration != 'نامشخص';
    final items = <Widget>[
      if (item.year > 0)
        _metaItem(
          Icons.calendar_today_rounded,
          item.yearText,
          color: palette.textSecondary,
        ),
      if (item.imdb > 0)
        _metaItem(Icons.star_rounded, item.imdbText, color: AppColors.gold),
      if (hasDuration)
        _metaItem(
          Icons.schedule_rounded,
          duration,
          color: palette.textSecondary,
        ),
      if (item.countries.isNotEmpty)
        _metaItem(
          Icons.public_rounded,
          item.countries.first.title,
          color: palette.textSecondary,
        ),
    ];
    final age = ageRatingFromDescription(item.description);
    if (age != null) {
      items.add(
        Text(
          age,
          style: TextStyle(
            fontFamily: AppTheme.fontFamily,
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: palette.textTertiary,
          ),
        ),
      );
    }
    return items;
  }

  Widget _metaItem(IconData icon, String text, {required Color color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontFamily: AppTheme.fontFamily,
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _genreChip(String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.32)),
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontFamily: AppTheme.fontFamily,
          fontSize: 10.5,
          fontWeight: FontWeight.w500,
          color: AppColors.accentSoft,
        ),
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
    bool autofocus = false,
    Color? iconColor,
  }) {
    return AppFocusable(
      onTap: onTap,
      autofocus: autofocus,
      borderRadius: 999,
      focusScale: 1.08,
      child: Tooltip(
        message: tooltip,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.48),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Icon(icon, color: iconColor ?? Colors.white, size: 20),
          ),
        ),
      ),
    );
  }

  // MARK: Action bar

  Widget _actions(MediaItem item) {
    final history = AppServices.instance.history.entryFor(item);
    final canPlay = item.playableSources.isNotEmpty;

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (item.isSeries || canPlay)
          FilledButton.icon(
            onPressed: _playMain,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.play_arrow_rounded, size: 21),
            label: Text(
              history != null && history.progress > 0.02
                  ? 'ادامه تماشا'
                  : (item.isSeries ? 'پخش قسمت اول' : 'پخش'),
            ),
          ),
        ListenableBuilder(
          listenable: AppServices.instance.favorites,
          builder: (context, _) {
            final isFavorite = AppServices.instance.favorites.isFavorite(item);
            return OutlinedButton.icon(
              onPressed: () => _toggleFavorite(item),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: Icon(
                isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: isFavorite ? AppColors.red : null,
                size: 19,
              ),
              label: Text(
                isFavorite ? 'در علاقه‌مندی‌ها' : 'افزودن به علاقه‌مندی‌ها',
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _toggleFavorite(MediaItem item) async {
    final added = await AppServices.instance.favorites.toggle(item);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          added ? 'به علاقه‌مندی‌ها اضافه شد' : 'از علاقه‌مندی‌ها حذف شد',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // MARK: Story

  Widget _storySection(MediaItem item) {
    final palette = context.palette;
    final cleaned = cleanDescription(item.description);
    final isLong = cleaned.length > 280;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          item.isSeries ? 'داستان سریال' : 'داستان فیلم',
          icon: Icons.notes_rounded,
        ),
        const SizedBox(height: 10),
        Text(
          cleaned.isEmpty ? 'توضیحی ثبت نشده است.' : cleaned,
          maxLines: _descriptionExpanded ? null : 6,
          overflow: _descriptionExpanded
              ? TextOverflow.visible
              : TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: AppTheme.fontFamily,
            fontSize: 13,
            height: 1.9,
            color: cleaned.isEmpty
                ? palette.textTertiary
                : palette.textSecondary,
          ),
        ),
        if (isLong)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: AppFocusable(
              onTap: () =>
                  setState(() => _descriptionExpanded = !_descriptionExpanded),
              borderRadius: 8,
              focusScale: 1.02,
              child: Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _descriptionExpanded ? 'کمتر' : 'بیشتر',
                      style: const TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.accentBright,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(
                      _descriptionExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 15,
                      color: AppColors.accentBright,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _sectionHeader(String title, {IconData? icon, String? trailing}) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16, color: AppColors.accentSoft),
          const SizedBox(width: 8),
        ],
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        if (trailing != null)
          Text(trailing, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  // MARK: Sources

  Widget _sourcesSection(List<MediaSource> sources) {
    if (sources.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionHeader('کیفیت‌های موجود', icon: Icons.high_quality_rounded),
          const SizedBox(height: 10),
          Text(
            'برای این عنوان سورس قابل پخشی ثبت نشده است.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          'کیفیت‌های موجود',
          icon: Icons.high_quality_rounded,
          trailing: '${faDigits(sources.length)} سورس',
        ),
        const SizedBox(height: 10),
        for (final source in sources)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppFocusable(
              onTap: () => _playSource(source),
              borderRadius: AppRadii.normal,
              focusScale: 1.01,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: context.palette.card,
                  borderRadius: BorderRadius.circular(AppRadii.normal),
                  border: Border.all(color: context.palette.stroke),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.play_circle_outline_rounded,
                      color: AppColors.accentBright,
                      size: 21,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        source.qualityLabel,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                    Text(
                      source.kindLabel,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(width: 10),
                    const Icon(Icons.chevron_left_rounded, size: 20),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // MARK: Episodes

  Widget _seriesSection() {
    return FutureBuilder<List<Season>>(
      future: _seasons,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: LoadingView(message: 'در حال دریافت قسمت‌ها…'),
          );
        }
        if (snapshot.hasError) {
          return ErrorView(
            message: snapshot.error.toString(),
            onRetry: _reloadSeasons,
          );
        }
        final seasons = (snapshot.data ?? const <Season>[])
            .where((season) => season.episodes.isNotEmpty)
            .toList();
        if (seasons.isEmpty) {
          return EmptyView(
            message: 'قسمتی برای این سریال ثبت نشده است.',
            icon: Icons.live_tv_rounded,
          );
        }
        final selected = _selectedSeason.clamp(0, seasons.length - 1);
        final season = seasons[selected];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionHeader(
              'قسمت‌ها',
              icon: Icons.playlist_play_rounded,
              trailing: '${faDigits(season.episodes.length)} قسمت',
            ),
            const SizedBox(height: 10),
            if (seasons.length > 1)
              SizedBox(
                height: 40,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: seasons.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final isSelected = index == selected;
                    return AppFocusable(
                      onTap: () => setState(() => _selectedSeason = index),
                      borderRadius: 999,
                      focusScale: 1.03,
                      child: Container(
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
                          seasons[index].title,
                          style: TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: 12.5,
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isSelected
                                ? Colors.white
                                : context.palette.textSecondary,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            const SizedBox(height: 10),
            ListenableBuilder(
              listenable: AppServices.instance.history,
              builder: (context, _) {
                final watched = AppServices.instance.history.watchedEpisodeIds(
                  widget.item.id,
                );
                return Column(
                  children: [
                    for (final episode in season.episodes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _EpisodeTile(
                          episode: episode,
                          isWatched: watched.contains(episode.id),
                          onTap: episode.playableSources.isEmpty
                              ? null
                              : () => _playEpisode(season, episode),
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }

  Widget _similarSection(MediaItem item) {
    return FutureBuilder<List<MediaItem>>(
      future: _similar,
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <MediaItem>[];
        if (items.isEmpty) return const SizedBox.shrink();
        return MediaRail(
          title: 'عناوین مشابه',
          subtitle: 'در ${item.genres.first.title}',
          items: items,
          onOpen: _openItem,
        );
      },
    );
  }

  void _openItem(MediaItem item) {
    Navigator.of(context).push(appRoute(DetailScreen(item: item)));
  }

  void _playMain() {
    final item = widget.item;
    if (!item.isSeries) {
      final sources = item.playableSources;
      if (sources.isEmpty) return;
      final historyEntry = AppServices.instance.history.entryFor(item);
      _openPlayer(
        PlayerArgs.forMovie(item),
        startAt: historyEntry?.progress ?? 0,
      );
      return;
    }
    final seasonsFuture = _seasons;
    if (seasonsFuture == null) return;
    seasonsFuture.then((seasons) {
      if (!mounted) return;
      for (final season in seasons) {
        for (final episode in season.episodes) {
          if (episode.playableSources.isNotEmpty) {
            _playEpisode(season, episode);
            return;
          }
        }
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('قسمت قابل پخشی پیدا نشد')));
    });
  }

  void _playSource(MediaSource source) {
    final args = PlayerArgs(
      title: widget.item.title,
      subtitle: widget.item.yearText,
      posterUrl: widget.item.image,
      sources: [source],
      preferredSourceId: source.id,
      media: widget.item,
    );
    _openPlayer(args);
  }

  void _playEpisode(Season season, Episode episode) {
    _openPlayer(PlayerArgs.forEpisode(widget.item, season, episode));
  }

  void _openPlayer(PlayerArgs args, {double startAt = 0}) {
    Navigator.of(context)
        .push(appRoute(PlayerScreen(args: args, startAt: startAt)));
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.episode,
    required this.isWatched,
    required this.onTap,
  });

  final Episode episode;
  final bool isWatched;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final number = episode.episodeNumber;
    return AppFocusable(
      onTap: onTap ?? () {},
      enabled: onTap != null,
      borderRadius: AppRadii.normal,
      focusScale: 1.01,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: context.palette.card,
          borderRadius: BorderRadius.circular(AppRadii.normal),
          border: Border.all(color: context.palette.stroke),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isWatched
                    ? AppColors.green.withValues(alpha: 0.16)
                    : AppColors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: isWatched
                  ? const Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: AppColors.green,
                    )
                  : Text(
                      number == null ? '•' : faDigits(number),
                      style: const TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppColors.accentBright,
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    episode.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  if (episode.duration != null)
                    Text(
                      episode.duration!,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            Icon(
              onTap == null
                  ? Icons.block_rounded
                  : Icons.play_circle_outline_rounded,
              color: onTap == null
                  ? context.palette.textTertiary
                  : AppColors.accentBright,
            ),
          ],
        ),
      ),
    );
  }
}
