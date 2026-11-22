import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/app_events.dart';
import '../core/catalogue.dart';
import '../core/description_text.dart';
import '../core/media_filters.dart';
import '../core/models.dart';
import '../core/origin_filter.dart';
import '../core/playback.dart';
import '../core/stores.dart';
import '../ui/nav.dart';
import '../ui/shell.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'browse_screen.dart';
import 'detail_screen.dart';
import 'player_screen.dart';
import 'search_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final PageController _pageController = PageController();
  Timer? _autoPlay;

  bool _loading = true;
  String? _error;
  List<MediaItem> _latestMovies = const [];
  List<MediaItem> _latestSeries = const [];
  List<MediaItem> _topMovies = const [];
  List<MediaItem> _topSeries = const [];
  List<Genre> _genres = const [];
  int _slide = 0;

  late final AppSettings _settings;
  late bool _lastHideOrigins;
  late bool _lastHideAnime;

  ContentHiding get _hiding => ContentHiding(
    origins: _settings.hideRegionalOrigins,
    anime: _settings.hideAnime,
  );

  List<MediaItem> get _slides => mixHeroSlides(
    _latestMovies,
    _latestSeries,
  ).where((item) => !_hiding.isHidden(item)).toList();

  List<Genre> get _visibleGenres {
    if (!_settings.hideRegionalOrigins) return _genres;
    return _genres
        .where((genre) => !OriginFilter.hidesGenre(genre.title))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _settings = AppServices.instance.settings;
    _lastHideOrigins = _settings.hideRegionalOrigins;
    _lastHideAnime = _settings.hideAnime;
    _settings.addListener(_onSettingsChanged);
    AppEvents.refreshTick.addListener(_onRefreshTick);
    _load();
  }

  @override
  void dispose() {
    _autoPlay?.cancel();
    _settings.removeListener(_onSettingsChanged);
    AppEvents.refreshTick.removeListener(_onRefreshTick);
    _pageController.dispose();
    super.dispose();
  }

  void _onRefreshTick() {
    if (mounted) _load();
  }

  void _onSettingsChanged() {
    if (!mounted) return;
    final origins = _settings.hideRegionalOrigins;
    final anime = _settings.hideAnime;
    if (origins != _lastHideOrigins || anime != _lastHideAnime) {
      _lastHideOrigins = origins;
      _lastHideAnime = anime;
      // Rails are filtered while loading, so new hiding rules need fresh
      // pages; otherwise a rail can empty out even though more titles exist.
      _load();
      return;
    }
    final needsJump = _slide >= _slides.length;
    setState(() {
      // Filtering a hero title out shrinks the PageView; never leave the
      // controller pointing past the last slide.
      if (needsJump) _slide = 0;
    });
    if (needsJump) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(0);
        }
      });
    }
    _startAutoPlay();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = ApiClient.instance;
    final hiding = _hiding;
    String? firstError;

    /// Hidden titles are dropped client-side, so walk a few pages to keep the
    /// rail populated; mirrors `HomeModel.loadMovies/loadSeries`.
    Future<List<MediaItem>> loadRail({
      required bool isSeries,
      required SortOption sort,
    }) async {
      final merged = <MediaItem>[];
      final seen = <int>{};
      for (var page = 0; page < 3; page++) {
        try {
          final items = isSeries
              ? await api.series(page: page, sort: sort)
              : await api.movies(page: page, sort: sort);
          for (final item in items) {
            if (seen.add(item.id)) merged.add(item);
          }
        } catch (error) {
          if (merged.isEmpty) firstError ??= error.toString();
          break;
        }
        if (!hiding.isActive ||
            merged.where((item) => !hiding.isHidden(item)).length >=
                filterScanMinimumMatches) {
          break;
        }
      }
      return hiding.isActive
          ? merged.where((item) => !hiding.isHidden(item)).toList()
          : merged;
    }

    final results = await Future.wait([
      loadRail(isSeries: false, sort: SortOption.newest),
      loadRail(isSeries: true, sort: SortOption.newest),
      loadRail(isSeries: false, sort: SortOption.imdb),
      loadRail(isSeries: true, sort: SortOption.imdb),
    ]);
    final genres = await Catalogue.genres().catchError(
      (Object _) => const <Genre>[],
    );

    if (!mounted) return;
    final empty = results.every((list) => list.isEmpty);
    setState(() {
      _latestMovies = results[0];
      _latestSeries = results[1];
      _topMovies = results[2];
      _topSeries = results[3];
      _genres = genres;
      _loading = false;
      _error = empty
          ? (firstError ??
                (hiding.isActive ? null : 'محتوایی برای نمایش پیدا نشد'))
          : null;
      _slide = 0;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    });
    _startAutoPlay();
  }

  void _startAutoPlay() {
    _autoPlay?.cancel();
    if (_slides.length < 2) return;
    _autoPlay = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted || !_pageController.hasClients) return;
      final next = (_slide + 1) % _slides.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeInOut,
      );
    });
  }

  void _goToSlide(int index) {
    if (_slides.isEmpty) return;
    final target = (index + _slides.length) % _slides.length;
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeInOut,
    );
  }

  void _open(MediaItem item) {
    Navigator.of(context).push(appRoute(DetailScreen(item: item)));
  }

  void _play(MediaItem item) {
    if (item.isSeries) {
      _open(item);
      return;
    }
    if (item.playableSources.isEmpty) {
      _open(item);
      return;
    }
    Navigator.of(context)
        .push(appRoute(PlayerScreen(args: PlayerArgs.forMovie(item))));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _latestMovies.isEmpty && _latestSeries.isEmpty) {
      return const LoadingView(message: 'در حال دریافت کاتالوگ…');
    }
    if (_error != null && _slides.isEmpty) {
      return ErrorView(message: _error!, onRetry: _load);
    }
    if (_hiding.isActive &&
        _latestMovies.isEmpty &&
        _latestSeries.isEmpty &&
        _topMovies.isEmpty &&
        _topSeries.isEmpty) {
      return const EmptyView(
        icon: Icons.visibility_off_outlined,
        title: 'محتوایی برای نمایش نیست',
        message: 'همهٔ عناوین این بخش در تنظیمات پنهان شده‌اند. برای نمایش، گزینه‌های «پنهان‌سازی محتوا» را تغییر دهید.',
      );
    }

    final history = AppServices.instance.history;
    final hiding = _hiding;
    final recent = history.entries
        .map((entry) => entry.item)
        .where((item) => !hiding.isHidden(item))
        .take(12)
        .toList();
    final latestMovies = _latestMovies
        .where((item) => !hiding.isHidden(item))
        .take(20)
        .toList();
    final latestSeries = _latestSeries
        .where((item) => !hiding.isHidden(item))
        .take(20)
        .toList();
    final topMovies = _topMovies
        .where((item) => !hiding.isHidden(item))
        .take(20)
        .toList();
    final topSeries = _topSeries
        .where((item) => !hiding.isHidden(item))
        .take(20)
        .toList();
    final genres = _visibleGenres;

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              sliver: SliverToBoxAdapter(child: _topBar()),
            ),
            if (_slides.isNotEmpty) SliverToBoxAdapter(child: _hero()),
            SliverToBoxAdapter(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1280),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 26),
                    if (recent.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: MediaRail(
                          title: 'ادامه تماشا',
                          subtitle: 'اخیراً دیده‌شده',
                          items: recent,
                          onOpen: _open,
                          onSeeAll: () =>
                              ShellScope.of(context).selectTab(AppTab.history),
                        ),
                      ),
                    if (_latestMovies.isNotEmpty && latestMovies.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 26, 16, 0),
                        child: MediaRail(
                          title: 'آخرین فیلم‌های اضافه‌شده',
                          subtitle: 'تازه‌ترین‌ها',
                          items: latestMovies,
                          onOpen: _open,
                          onSeeAll: () =>
                              ShellScope.of(context).selectTab(AppTab.movies),
                        ),
                      ),
                    if (_latestSeries.isNotEmpty && latestSeries.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 26, 16, 0),
                        child: MediaRail(
                          title: 'آخرین سریال‌ها',
                          subtitle: 'تازه‌ترین قسمت‌ها',
                          items: latestSeries,
                          onOpen: _open,
                          onSeeAll: () =>
                              ShellScope.of(context).selectTab(AppTab.series),
                        ),
                      ),
                    if (_topMovies.isNotEmpty && topMovies.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 26, 16, 0),
                        child: MediaRail(
                          title: 'برترین فیلم‌ها',
                          subtitle: 'بر اساس IMDb',
                          items: topMovies,
                          onOpen: _open,
                          onSeeAll: () =>
                              ShellScope.of(context).selectTab(AppTab.movies),
                        ),
                      ),
                    if (_topSeries.isNotEmpty && topSeries.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 26, 16, 0),
                        child: MediaRail(
                          title: 'برترین سریال‌ها',
                          subtitle: 'بر اساس IMDb',
                          items: topSeries,
                          onOpen: _open,
                          onSeeAll: () =>
                              ShellScope.of(context).selectTab(AppTab.series),
                        ),
                      ),
                    if (genres.isNotEmpty) ...[
                      const SizedBox(height: 30),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: SectionHeader(
                          title: 'دسته‌بندی‌ها',
                          actionLabel: 'همه',
                          onAction: () =>
                              ShellScope.of(context)
                                  .selectTab(AppTab.categories),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final genre in genres.take(18))
                              AppFocusable(
                                onTap: () => Navigator.of(context).push(
                                  appRoute(GenreBrowseScreen(genre: genre)),
                                ),
                                borderRadius: 999,
                                focusScale: 1.03,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 15,
                                    vertical: 9,
                                  ),
                                  decoration: BoxDecoration(
                                    color: context.palette.card,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: context.palette.stroke,
                                    ),
                                  ),
                                  child: Text(
                                    genre.title,
                                    style: TextStyle(
                                      fontFamily: AppTheme.fontFamily,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                      color: context.palette.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    final palette = context.palette;
    return Row(
      children: [
        Image.asset(
          context.isDark ? 'assets/logo-dark.png' : 'assets/logo.png',
          width: 34,
          height: 34,
          errorBuilder: (_, _, _) =>
              const Icon(Icons.cloud_rounded, color: AppColors.accent),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('CCloud', style: Theme.of(context).textTheme.titleLarge),
              Text(
                'فیلم، سریال و پخش زنده',
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 10.5,
                  color: palette.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        AppFocusable(
          onTap: _load,
          borderRadius: 999,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: palette.card,
              shape: BoxShape.circle,
              border: Border.all(color: palette.stroke),
            ),
            child: Icon(
              Icons.refresh_rounded,
              color: palette.textSecondary,
              size: 21,
            ),
          ),
        ),
        const SizedBox(width: 8),
        AppFocusable(
          onTap: () =>
              Navigator.of(context).push(appRoute(const SearchScreen())),
          borderRadius: 999,
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: palette.card,
              shape: BoxShape.circle,
              border: Border.all(color: palette.stroke),
            ),
            child: Icon(
              Icons.search_rounded,
              color: palette.textSecondary,
              size: 21,
            ),
          ),
        ),
      ],
    );
  }

  Widget _hero() {
    final slides = _slides;
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 760;
    // Mirrors the macOS hero: a 430pt slab that bleeds into the page edges.
    // On short TV viewports keep it clear of the first rail.
    final height = wide
        ? (size.height * 0.56).clamp(300.0, 430.0)
        : (size.width * 0.98).clamp(300.0, 400.0);
    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: slides.length,
            onPageChanged: (index) {
              setState(() => _slide = index);
              _startAutoPlay();
            },
            itemBuilder: (context, index) => _HeroSlide(
              item: slides[index],
              onPlay: () => _play(slides[index]),
              onDetails: () => _open(slides[index]),
            ),
          ),
          if (slides.length > 1) ...[
            Positioned(
              top: 14,
              left: 14,
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Row(
                  children: [
                    AppFocusable(
                      onTap: () => _goToSlide(_slide + 1),
                      borderRadius: 999,
                      focusScale: 1.1,
                      child: _navDot(Icons.chevron_left_rounded),
                    ),
                    const SizedBox(width: 8),
                    AppFocusable(
                      onTap: () => _goToSlide(_slide - 1),
                      borderRadius: 999,
                      focusScale: 1.1,
                      child: _navDot(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 22,
              bottom: wide ? 18 : 12,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.38),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  children: [
                    for (var index = 0; index < slides.length; index++)
                      AppFocusable(
                        onTap: () => _goToSlide(index),
                        borderRadius: 999,
                        focusScale: 1.25,
                        showHighlight: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 3,
                            vertical: 2,
                          ),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: index == _slide ? 20 : 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: index == _slide
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.36),
                              borderRadius: BorderRadius.circular(99),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _navDot(IconData icon) => Container(
    width: 34,
    height: 34,
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.42),
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
    ),
    child: Icon(icon, color: Colors.white, size: 20),
  );
}

class _HeroSlide extends StatelessWidget {
  const _HeroSlide({
    required this.item,
    required this.onPlay,
    required this.onDetails,
  });

  final MediaItem item;
  final VoidCallback onPlay;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final image = item.cover.isNotEmpty ? item.cover : item.image;
    final summary = plotFromDescription(item.description);
    final country = item.countries.isEmpty ? null : item.countries.first.title;

    return Stack(
      fit: StackFit.expand,
      children: [
        AsyncImage(url: image, placeholderIcon: Icons.movie_rounded),
        // Mirrors the macOS hero scrims: the leading (right, in RTL) edge is
        // dark enough for text, the artwork stays visible towards the trailing
        // edge, and the slab melts into the page background at the bottom.
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerRight,
              end: Alignment.centerLeft,
              colors: [
                Colors.black.withValues(alpha: 0.92),
                Colors.black.withValues(alpha: 0.58),
                Colors.black.withValues(alpha: 0.10),
                Colors.transparent,
              ],
              stops: const [0, 0.38, 0.78, 1],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.38),
                Colors.transparent,
              ],
              stops: const [0, 0.16],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.55),
                Colors.black.withValues(alpha: 0.18),
              ],
              stops: const [0.42, 0.82, 1],
            ),
          ),
        ),
        Builder(
          builder: (context) {
            final bg = Theme.of(context).scaffoldBackgroundColor;
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    bg.withValues(alpha: 0),
                    bg.withValues(alpha: 0.55),
                    bg,
                  ],
                  stops: const [0.66, 0.86, 1],
                ),
              ),
            );
          },
        ),
        Align(
          alignment: Alignment.bottomRight,
          child: LayoutBuilder(
            builder: (context, box) {
              // TV viewports are only ~540pt tall; the desktop hero padding
              // would push the action buttons out of the slab.
              final compact = box.maxHeight < 360;
              final horizontal = wide ? (compact ? 32.0 : 44.0) : 20.0;
              final bottom = compact ? 26.0 : (wide ? 88.0 : 22.0);
              return Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontal,
                  compact ? 10 : 20,
                  horizontal,
                  bottom,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: wide ? 600 : 520),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          item.isSeries ? 'سریال' : 'فیلم',
                          style: const TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: AppTheme.fontFamily,
                          fontSize: compact ? 26 : (wide ? 31 : 25),
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                          color: Colors.white,
                          shadows: const [
                            Shadow(color: Colors.black54, blurRadius: 6),
                          ],
                        ),
                      ),
                      if (summary != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          summary,
                          maxLines: compact ? 2 : (wide ? 3 : 2),
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: compact ? 11.5 : (wide ? 12.5 : 12),
                            height: compact ? 1.6 : 1.7,
                            color: Colors.white.withValues(alpha: 0.84),
                          ),
                        ),
                      ],
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          if (item.year > 0)
                            _meta(Icons.calendar_today_rounded, item.yearText),
                          if (item.imdb > 0)
                            _meta(
                              Icons.star_rounded,
                              item.imdbText,
                              tint: AppColors.gold,
                            ),
                          if (country != null)
                            _meta(Icons.public_rounded, country),
                        ],
                      ),
                      if (item.genres.isNotEmpty) ...[
                        const SizedBox(height: 9),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final genre in item.genres.take(3))
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.20),
                                  ),
                                ),
                                child: Text(
                                  genre.title,
                                  style: TextStyle(
                                    fontFamily: AppTheme.fontFamily,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white.withValues(alpha: 0.88),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: onPlay,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: Colors.black,
                              minimumSize: const Size(0, 40),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              textStyle: const TextStyle(
                                fontFamily: AppTheme.fontFamily,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            icon: const Icon(
                              Icons.play_arrow_rounded,
                              size: 20,
                            ),
                            label: Text(
                              item.isSeries ? 'مشاهده قسمت‌ها' : 'پخش فیلم',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: onDetails,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.14,
                              ),
                              side: BorderSide(
                                color: Colors.white.withValues(alpha: 0.28),
                              ),
                              minimumSize: const Size(0, 40),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              textStyle: const TextStyle(
                                fontFamily: AppTheme.fontFamily,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            icon: const Icon(
                              Icons.info_outline_rounded,
                              size: 17,
                            ),
                            label: const Text('جزئیات'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _meta(IconData icon, String text, {Color? tint}) {
    final color = tint ?? Colors.white.withValues(alpha: 0.82);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
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
}
