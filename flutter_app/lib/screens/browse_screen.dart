import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/catalogue.dart';
import '../core/models.dart';
import '../core/origin_filter.dart';
import '../core/stores.dart';
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
  final ScrollController _scrollController = ScrollController();

  final List<MediaItem> _items = [];
  List<Genre> _genres = const [];
  late int _genreId = widget.initialGenreId;
  SortOption _sort = SortOption.newest;

  int _page = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _end = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadGenres();
    _reload();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
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
        !_end &&
        !_loading) {
      _loadMore();
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _end = false;
      _page = 0;
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
        _end = items.length < 30;
        _page = 0;
      });
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
        _items.addAll(items
            .where((item) => !_items.any((existing) =>
                existing.id == item.id && existing.isSeries == item.isSeries))
            .toList());
        _page = nextPage;
        _end = items.length < 30;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<List<MediaItem>> _fetch(int page) {
    final api = ApiClient.instance;
    return widget.kind == BrowseKind.movies
        ? api.movies(page: page, genreId: _genreId, sort: _sort)
        : api.series(page: page, genreId: _genreId, sort: _sort);
  }

  List<MediaItem> _visibleItems(AppSettings settings) {
    return _items.where((item) {
      if (settings.hideRegionalOrigins && OriginFilter.hides(item)) {
        return false;
      }
      if (settings.hideAnime && OriginFilter.hidesAnime(item)) {
        return false;
      }
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
                          child: Icon(Icons.refresh_rounded,
                              size: 20, color: context.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              if (widget.showChrome && _genres.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: FilterPills(
                    values: [0, ..._genres.map((g) => g.id)],
                    selected: _genreId,
                    labelBuilder: (value) {
                      if (value == 0) return 'همه';
                      for (final genre in _genres) {
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
                    Text('مرتب‌سازی:',
                        style: Theme.of(context).textTheme.bodySmall),
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
                  ],
                ),
              ),
              Expanded(
                child: _body(items, maxExtent),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _body(List<MediaItem> items, double maxExtent) {
    if (_loading && items.isEmpty) {
      return const LoadingView(message: 'در حال دریافت کاتالوگ…');
    }
    if (_error != null && items.isEmpty) {
      return ErrorView(message: _error!, onRetry: _reload);
    }
    if (items.isEmpty) {
      return EmptyView(
        message: _genreId == 0
            ? 'محتوایی برای نمایش پیدا نشد.'
            : 'در این دسته‌بندی چیزی پیدا نشد.',
        icon: Icons.movie_filter_outlined,
      );
    }
    return RefreshIndicator(
      onRefresh: _reload,
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
            onTap: () => Navigator.of(context)
                .push(appRoute(DetailScreen(item: item))),
          );
        },
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
  final ScrollController _scrollController = ScrollController();
  final List<MediaItem> _items = [];
  SortOption _sort = SortOption.newest;
  int _page = 0;
  bool _loading = true;
  bool _loadingMore = false;
  bool _end = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      final position = _scrollController.position;
      if (position.pixels >= position.maxScrollExtent - 500 &&
          !_loadingMore &&
          !_end &&
          !_loading) {
        _loadMore();
      }
    });
    _reload();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _end = false;
      _page = 0;
      _items.clear();
    });
    try {
      final items = await ApiClient.instance.countryPosters(
        countryId: widget.country.id,
        page: 0,
        sort: _sort,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(items);
        _loading = false;
        _end = items.length < 30;
      });
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
      final items = await ApiClient.instance.countryPosters(
        countryId: widget.country.id,
        page: next,
        sort: _sort,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(items);
        _page = next;
        _end = items.length < 30;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                      : _items.isEmpty
                          ? const EmptyView(
                              message: 'برای این کشور عنوانی پیدا نشد.',
                              icon: Icons.public_off_rounded,
                            )
                          : GridView.builder(
                              controller: _scrollController,
                              padding:
                                  const EdgeInsets.fromLTRB(16, 8, 16, 30),
                              gridDelegate:
                                  const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 160,
                                mainAxisSpacing: 16,
                                crossAxisSpacing: 12,
                                childAspectRatio: 0.58,
                              ),
                              itemCount:
                                  _items.length + (_loadingMore ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index >= _items.length) {
                                  return const Center(
                                    child: SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  );
                                }
                                final item = _items[index];
                                return MediaPosterCard(
                                  item: item,
                                  width: double.infinity,
                                  onTap: () => Navigator.of(context).push(
                                      appRoute(DetailScreen(item: item))),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
