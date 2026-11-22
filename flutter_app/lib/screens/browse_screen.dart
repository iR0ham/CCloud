import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/app_events.dart';
import '../core/catalogue.dart';
import '../core/media_filters.dart';
import '../core/models.dart';
import '../core/origin_filter.dart';
import '../core/stores.dart';
import '../ui/feed_footer.dart';
import '../ui/media_filter_panel.dart';
import '../ui/nav.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'detail_screen.dart';

enum BrowseKind { movies, series }

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({
    super.key,
    required this.kind,
    this.initialGenreId = 0,
    this.showChrome = true,
  });

  final BrowseKind kind;
  final int initialGenreId;
  final bool showChrome;

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  static const int _pageSize = 30;

  final ScrollController _scrollController = ScrollController();

  final List<MediaItem> _items = [];
  List<Genre> _genres = const [];
  late int _genreId = widget.initialGenreId;
  SortOption _sort = SortOption.newest;
  MediaFilters _filters = const MediaFilters();

  int _page = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _end = false;
  bool _filterScanning = false;
  bool _scanningMore = false;
  int _scanGeneration = 0;
  String? _error;

  late final AppSettings _settings;
  late bool _lastHideOrigins;
  late bool _lastHideAnime;

  @override
  void initState() {
    super.initState();
    _settings = AppServices.instance.settings;
    _lastHideOrigins = _settings.hideRegionalOrigins;
    _lastHideAnime = _settings.hideAnime;
    _settings.addListener(_onSettingsChanged);
    AppEvents.refreshTick.addListener(_onRefreshTick);
    _scrollController.addListener(_onScroll);
    _loadGenres();
    _reload();
  }

  @override
  void dispose() {
    _scanGeneration += 1;
    _settings.removeListener(_onSettingsChanged);
    AppEvents.refreshTick.removeListener(_onRefreshTick);
    _scrollController.dispose();
    super.dispose();
  }

  void _onRefreshTick() {
    if (!mounted) return;
    // The shell invalidated the genre cache; refill the pills as macOS does.
    _loadGenres();
    _reload();
  }

  void _onSettingsChanged() {
    final origins = _settings.hideRegionalOrigins;
    final anime = _settings.hideAnime;
    if (origins == _lastHideOrigins && anime == _lastHideAnime) return;
    _lastHideOrigins = origins;
    _lastHideAnime = anime;
    if (!mounted) return;
    // A hidden genre can no longer stay selected; macOS falls back to «همه».
    Genre? selected;
    for (final genre in _genres) {
      if (genre.id == _genreId) selected = genre;
    }
    if (origins &&
        selected != null &&
        OriginFilter.hidesGenre(selected.title)) {
      _genreId = 0;
      _reload();
      return;
    }
    _startFilterScan();
  }

  Future<void> _loadGenres() async {
    try {
      final genres = await Catalogue.genres();
      if (mounted) setState(() => _genres = genres);
    } catch (_) {}
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 500 &&
        !_loadingMore &&
        !_filterScanning &&
        !_scanningMore &&
        !_end &&
        !_loading) {
      _loadMore();
    }
  }

  Future<void> _reload() async {
    _scanGeneration += 1;
    setState(() {
      _loading = true;
      _error = null;
      _end = false;
      _page = 0;
      _filterScanning = false;
      _scanningMore = false;
      _items.clear();
    });
    try {
      final items = await _fetch(0);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(items);
        _loading = false;
        _end = items.length < _pageSize;
        _page = 0;
      });
      _startFilterScan();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    final nextPage = _page + 1;
    try {
      final items = await _fetch(nextPage);
      if (!mounted) return;
      setState(() {
        _append(items);
        _page = nextPage;
        _end = items.length < _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// Appends [items], dropping titles already in the feed.
  void _append(List<MediaItem> items) {
    _items.addAll(
      items.where(
        (item) => !_items.any(
          (existing) =>
              existing.id == item.id && existing.isSeries == item.isSeries,
        ),
      ),
    );
  }

  bool get _isPostFiltering =>
      _filters.isActive || _settings.hideRegionalOrigins || _settings.hideAnime;

  /// Walks the feed forward (bounded) until enough visible titles exist.
  Future<void> _startFilterScan() async {
    final token = ++_scanGeneration;
    if (!_isPostFiltering) {
      if (_filterScanning || _scanningMore) {
        setState(() {
          _filterScanning = false;
          _scanningMore = false;
        });
      }
      return;
    }
    setState(() {
      _filterScanning = true;
      _scanningMore = false;
    });
    var scanned = 0;
    try {
      while (mounted && token == _scanGeneration) {
        final matches = _visibleItems(_settings).length;
        if (!shouldContinueFilterScan(
          matches: matches,
          pagesScanned: scanned,
          hasMore: !_end,
        )) {
          break;
        }
        final next = _page + 1;
        final fetched = await _fetch(next);
        if (!mounted || token != _scanGeneration) return;
        setState(() {
          _append(fetched);
          _page = next;
          _end = fetched.length < _pageSize;
        });
        scanned += 1;
      }
    } catch (_) {
      // The first page already loaded; a later page failing just ends the scan.
    } finally {
      if (mounted && token == _scanGeneration) {
        setState(() => _filterScanning = false);
      }
    }
  }

  /// Footer action: at most four more pages, stopping at the first new match.
  Future<void> _scanMore() async {
    if (_scanningMore || _filterScanning || _end) return;
    final token = _scanGeneration;
    final baseline = _visibleItems(_settings).length;
    setState(() => _scanningMore = true);
    var scanned = 0;
    try {
      while (mounted && token == _scanGeneration) {
        final added = _visibleItems(_settings).length - baseline;
        if (!shouldContinueScanMore(
          newMatches: added,
          pagesScanned: scanned,
          hasMore: !_end,
        )) {
          break;
        }
        final next = _page + 1;
        final fetched = await _fetch(next);
        if (!mounted || token != _scanGeneration) return;
        setState(() {
          _append(fetched);
          _page = next;
          _end = fetched.length < _pageSize;
        });
        scanned += 1;
      }
    } catch (_) {
      // Best effort; the empty state keeps its «بررسی عناوین بیشتر» action.
    } finally {
      if (mounted && token == _scanGeneration) {
        setState(() => _scanningMore = false);
      }
    }
  }

  void _applyFilters(MediaFilters value) {
    if (value == _filters) return;
    setState(() => _filters = value);
    _startFilterScan();
  }

  Future<void> _openFilters() async {
    // A movies or series feed cannot switch kind, so the panel hides it.
    final result = await showMediaFilterPanel(
      context,
      _filters,
      showKind: false,
    );
    if (result != null) _applyFilters(result);
  }

  Future<List<MediaItem>> _fetch(int page) {
    final api = ApiClient.instance;
    return widget.kind == BrowseKind.movies
        ? api.movies(page: page, genreId: _genreId, sort: _sort)
        : api.series(page: page, genreId: _genreId, sort: _sort);
  }

  List<Genre> get _visibleGenres {
    if (!_settings.hideRegionalOrigins) return _genres;
    return _genres
        .where((genre) => !OriginFilter.hidesGenre(genre.title))
        .toList();
  }

  List<MediaItem> _visibleItems(AppSettings settings) {
    final hiding = ContentHiding(
      origins: settings.hideRegionalOrigins,
      anime: settings.hideAnime,
    );
    return _items.where((item) {
      if (hiding.isHidden(item)) return false;
      if (_filters.isActive && !_filters.matches(item)) return false;
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final settings = AppServices.instance.settings;
    final isTv = MediaQuery.sizeOf(context).width >= 760;
    final maxExtent = isTv ? 180.0 : 150.0;

    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          // Recompute inside the listener so toggling hiding off restores the
          // genre pills without waiting for another reload.
          final genres = _visibleGenres;
          final items = _visibleItems(settings);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.showChrome)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.kind == BrowseKind.movies
                                  ? 'فیلم‌ها'
                                  : 'سریال‌ها',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            Text(
                              'کاتالوگ کامل CCloud',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      AppFocusable(
                        onTap: _reload,
                        borderRadius: 999,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: context.palette.card,
                            shape: BoxShape.circle,
                            border: Border.all(color: context.palette.stroke),
                          ),
                          child: Icon(
                            Icons.refresh_rounded,
                            size: 20,
                            color: context.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (widget.showChrome && genres.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: FilterPills(
                    values: [0, ...genres.map((g) => g.id)],
                    selected: _genreId,
                    labelBuilder: (value) {
                      if (value == 0) return 'همه';
                      for (final genre in genres) {
                        if (genre.id == value) return genre.title;
                      }
                      return '';
                    },
                    onSelected: (value) {
                      if (value == _genreId) return;
                      setState(() => _genreId = value);
                      _reload();
                    },
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: Row(
                  children: [
                    Text(
                      'مرتب‌سازی:',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilterPills(
                        values: SortOption.values
                            .map((option) => option.index)
                            .toList(),
                        selected: _sort.index,
                        labelBuilder: (value) => SortOption.values[value].title,
                        onSelected: (value) {
                          final option = SortOption.values[value];
                          if (option == _sort) return;
                          setState(() => _sort = option);
                          _reload();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    MediaFilterButton(
                      filters: _filters,
                      showKind: false,
                      onTap: _openFilters,
                    ),
                  ],
                ),
              ),
              if (_filters.isActive)
                ActiveMediaFilterChips(
                  filters: _filters,
                  showKind: false,
                  onChange: _applyFilters,
                ),
              Expanded(child: _body(items, maxExtent, settings)),
            ],
          );
        },
      ),
    );
  }

  Widget _body(List<MediaItem> items, double maxExtent, AppSettings settings) {
    if (_loading && items.isEmpty) {
      return const LoadingView(message: 'در حال دریافت کاتالوگ…');
    }
    if (_error != null && items.isEmpty) {
      return ErrorView(message: _error!, onRetry: _reload);
    }
    if (_filterScanning && items.isEmpty) {
      return _filters.isActive
          ? const MediaFilterScanningView()
          : const LoadingView(message: 'در حال بررسی عناوین…');
    }
    if (items.isEmpty) {
      if (_filters.isActive) {
        return MediaFilteredEmptyView(
          hasMore: !_end,
          scanningMore: _scanningMore,
          onScanMore: _scanMore,
          onClear: () => _applyFilters(const MediaFilters()),
        );
      }
      final hiding = ContentHiding(
        origins: settings.hideRegionalOrigins,
        anime: settings.hideAnime,
      );
      if (hiding.isActive && _items.isNotEmpty) {
        final movies = widget.kind == BrowseKind.movies;
        return EmptyView(
          icon: Icons.visibility_off_outlined,
          title: movies
              ? 'همهٔ فیلم‌ها پنهان شده‌اند'
              : 'همهٔ سریال‌ها پنهان شده‌اند',
          message: movies
              ? 'همهٔ فیلم‌های این فهرست در دسته‌های پنهان‌شده قرار دارند. برای نمایش، گزینه‌های «پنهان‌سازی محتوا» را در تنظیمات تغییر دهید.'
              : 'همهٔ سریال‌های این فهرست در دسته‌های پنهان‌شده قرار دارند. برای نمایش، گزینه‌های «پنهان‌سازی محتوا» را در تنظیمات تغییر دهید.',
        );
      }
      return EmptyView(
        message: _genreId == 0
            ? 'محتوایی برای نمایش پیدا نشد.'
            : 'در این دسته‌بندی چیزی پیدا نشد.',
        icon: Icons.movie_filter_outlined,
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: Column(
        children: [
          Expanded(
            child: GridView.builder(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
              gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: maxExtent,
                mainAxisSpacing: 16,
                crossAxisSpacing: 12,
                childAspectRatio: 0.58,
              ),
              itemCount: items.length + (_loadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= items.length) {
                  return const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                final item = items[index];
                return MediaPosterCard(
                  item: item,
                  width: double.infinity,
                  onTap: () =>
                      Navigator.of(context)
                          .push(appRoute(DetailScreen(item: item))),
                );
              },
            ),
          ),
          BrowseFeedFooter(
            loadingMore: _loadingMore,
            // A running «بررسی عناوین بیشتر» is also a scan; showing the
            // action again would invite taps that do nothing.
            filterScanning: _filterScanning || _scanningMore,
            filterActive: _isPostFiltering,
            hasMore: !_end,
            itemCount: items.length,
            onScanMore: _scanMore,
          ),
        ],
      ),
    );
  }
}

/// One genre from the categories screen, with a Movies/Series switch.
class GenreBrowseScreen extends StatefulWidget {
  const GenreBrowseScreen({super.key, required this.genre});

  final Genre genre;

  @override
  State<GenreBrowseScreen> createState() => _GenreBrowseScreenState();
}

class _GenreBrowseScreenState extends State<GenreBrowseScreen> {
  BrowseKind _kind = BrowseKind.movies;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.genre.title),
        leading: Padding(
          padding: const EdgeInsets.all(8),
          child: AppFocusable(
            onTap: () => Navigator.of(context).maybePop(),
            borderRadius: 999,
            focusScale: 1.08,
            child: const Icon(Icons.arrow_forward_rounded),
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: FilterPills(
                      values: const [0, 1],
                      selected: _kind.index,
                      labelBuilder: (value) =>
                          value == 0 ? 'فیلم‌ها' : 'سریال‌ها',
                      onSelected: (value) =>
                          setState(() => _kind = BrowseKind.values[value]),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: KeyedSubtree(
                key: ValueKey(_kind),
                child: BrowseScreen(
                  kind: _kind,
                  initialGenreId: widget.genre.id,
                  showChrome: false,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// All posters for one country (movies and series mixed).
class CountryBrowseScreen extends StatefulWidget {
  const CountryBrowseScreen({super.key, required this.country});

  final Country country;

  @override
  State<CountryBrowseScreen> createState() => _CountryBrowseScreenState();
}

class _CountryBrowseScreenState extends State<CountryBrowseScreen> {
  static const int _pageSize = 30;

  final ScrollController _scrollController = ScrollController();
  final List<MediaItem> _items = [];
  SortOption _sort = SortOption.newest;
  int _page = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _end = false;
  bool _filterScanning = false;
  bool _scanningMore = false;
  int _scanGeneration = 0;
  String? _error;

  late final AppSettings _settings;
  late bool _lastHideOrigins;
  late bool _lastHideAnime;

  @override
  void initState() {
    super.initState();
    _settings = AppServices.instance.settings;
    _lastHideOrigins = _settings.hideRegionalOrigins;
    _lastHideAnime = _settings.hideAnime;
    _settings.addListener(_onSettingsChanged);
    AppEvents.refreshTick.addListener(_onRefreshTick);
    _scrollController.addListener(_onScroll);
    _reload();
  }

  @override
  void dispose() {
    _scanGeneration += 1;
    _settings.removeListener(_onSettingsChanged);
    AppEvents.refreshTick.removeListener(_onRefreshTick);
    _scrollController.dispose();
    super.dispose();
  }

  void _onRefreshTick() {
    if (mounted) _reload();
  }

  void _onSettingsChanged() {
    final origins = _settings.hideRegionalOrigins;
    final anime = _settings.hideAnime;
    if (origins == _lastHideOrigins && anime == _lastHideAnime) return;
    _lastHideOrigins = origins;
    _lastHideAnime = anime;
    if (!mounted) return;
    // New hiding rules can empty the first pages; walk forward like macOS.
    _startFilterScan();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 500 &&
        !_loadingMore &&
        !_filterScanning &&
        !_scanningMore &&
        !_end &&
        !_loading) {
      _loadMore();
    }
  }

  bool get _isPostFiltering =>
      _settings.hideRegionalOrigins || _settings.hideAnime;

  List<MediaItem> get _visibleItems {
    final hiding = ContentHiding(
      origins: _settings.hideRegionalOrigins,
      anime: _settings.hideAnime,
    );
    return _items.where((item) => !hiding.isHidden(item)).toList();
  }

  /// Appends [items], dropping titles already in the feed.
  void _append(List<MediaItem> items) {
    _items.addAll(
      items.where(
        (item) => !_items.any(
          (existing) =>
              existing.id == item.id && existing.isSeries == item.isSeries,
        ),
      ),
    );
  }

  Future<List<MediaItem>> _fetch(int page) => ApiClient.instance.countryPosters(
    countryId: widget.country.id,
    page: page,
    sort: _sort,
  );

  Future<void> _reload() async {
    _scanGeneration += 1;
    setState(() {
      _loading = true;
      _error = null;
      _end = false;
      _page = 0;
      _filterScanning = false;
      _scanningMore = false;
      _items.clear();
    });
    try {
      final items = await _fetch(0);
      if (!mounted) return;
      setState(() {
        _items.addAll(items);
        _loading = false;
        _end = items.length < _pageSize;
      });
      _startFilterScan();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    final next = _page + 1;
    try {
      final items = await _fetch(next);
      if (!mounted) return;
      setState(() {
        _append(items);
        _page = next;
        _end = items.length < _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// Walks the feed forward (bounded) until enough visible titles exist.
  Future<void> _startFilterScan() async {
    final token = ++_scanGeneration;
    if (!_isPostFiltering) {
      if (_filterScanning || _scanningMore) {
        setState(() {
          _filterScanning = false;
          _scanningMore = false;
        });
      }
      return;
    }
    setState(() {
      _filterScanning = true;
      _scanningMore = false;
    });
    var scanned = 0;
    try {
      while (mounted && token == _scanGeneration) {
        final matches = _visibleItems.length;
        if (!shouldContinueFilterScan(
          matches: matches,
          pagesScanned: scanned,
          hasMore: !_end,
        )) {
          break;
        }
        final next = _page + 1;
        final fetched = await _fetch(next);
        if (!mounted || token != _scanGeneration) return;
        setState(() {
          _append(fetched);
          _page = next;
          _end = fetched.length < _pageSize;
        });
        scanned += 1;
      }
    } catch (_) {
      // The first page already loaded; a later page failing just ends the scan.
    } finally {
      if (mounted && token == _scanGeneration) {
        setState(() => _filterScanning = false);
      }
    }
  }

  /// Footer action: at most four more pages, stopping at the first new match.
  Future<void> _scanMore() async {
    if (_scanningMore || _filterScanning || _end) return;
    final token = _scanGeneration;
    final baseline = _visibleItems.length;
    setState(() => _scanningMore = true);
    var scanned = 0;
    try {
      while (mounted && token == _scanGeneration) {
        final added = _visibleItems.length - baseline;
        if (!shouldContinueScanMore(
          newMatches: added,
          pagesScanned: scanned,
          hasMore: !_end,
        )) {
          break;
        }
        final next = _page + 1;
        final fetched = await _fetch(next);
        if (!mounted || token != _scanGeneration) return;
        setState(() {
          _append(fetched);
          _page = next;
          _end = fetched.length < _pageSize;
        });
        scanned += 1;
      }
    } catch (_) {
      // Best effort; the empty state keeps its «بررسی عناوین بیشتر» action.
    } finally {
      if (mounted && token == _scanGeneration) {
        setState(() => _scanningMore = false);
      }
    }
  }

  Widget _emptyState() {
    if (_filterScanning) return const MediaFilterScanningView();
    if (_isPostFiltering) {
      return const EmptyView(
        icon: Icons.visibility_off_outlined,
        title: 'همهٔ عناوین پنهان شده‌اند',
        message: 'همهٔ عنوان‌های این کشور در تنظیمات پنهان شده‌اند. برای نمایش، گزینه‌های «پنهان‌سازی محتوا» را تغییر دهید.',
      );
    }
    return const EmptyView(
      icon: Icons.movie_filter_outlined,
      title: 'عنوانی برای این کشور نیست',
      message: 'مرتب‌سازی دیگری را امتحان کنید یا کشور دیگری را انتخاب کنید.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) {
        final items = _visibleItems;
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.country.title),
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: AppFocusable(
                onTap: () => Navigator.of(context).maybePop(),
                borderRadius: 999,
                focusScale: 1.08,
                child: const Icon(Icons.arrow_forward_rounded),
              ),
            ),
          ),
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                  child: FilterPills(
                    values: SortOption.values.map((e) => e.index).toList(),
                    selected: _sort.index,
                    labelBuilder: (value) => SortOption.values[value].title,
                    onSelected: (value) {
                      final option = SortOption.values[value];
                      if (option == _sort) return;
                      setState(() => _sort = option);
                      _reload();
                    },
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const LoadingView(message: 'در حال دریافت عنوان‌ها…')
                      : _error != null
                      ? ErrorView(message: _error!, onRetry: _reload)
                      : items.isEmpty
                      ? _emptyState()
                      : Column(
                          children: [
                            Expanded(
                              child: GridView.builder(
                                controller: _scrollController,
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  8,
                                  16,
                                  30,
                                ),
                                gridDelegate:
                                    const SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: 160,
                                      mainAxisSpacing: 16,
                                      crossAxisSpacing: 12,
                                      childAspectRatio: 0.58,
                                    ),
                                itemCount:
                                    items.length + (_loadingMore ? 1 : 0),
                                itemBuilder: (context, index) {
                                  if (index >= items.length) {
                                    return const Center(
                                      child: SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      ),
                                    );
                                  }
                                  final item = items[index];
                                  return MediaPosterCard(
                                    item: item,
                                    width: double.infinity,
                                    onTap: () => Navigator.of(
                                      context,
                                    ).push(appRoute(DetailScreen(item: item))),
                                  );
                                },
                              ),
                            ),
                            BrowseFeedFooter(
                              loadingMore: _loadingMore,
                              filterScanning: _filterScanning || _scanningMore,
                              filterActive: _isPostFiltering,
                              hasMore: !_end,
                              itemCount: items.length,
                              onScanMore: _scanMore,
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
