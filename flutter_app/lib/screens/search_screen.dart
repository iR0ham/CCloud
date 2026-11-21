import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/app_events.dart';
import '../core/models.dart';
import '../core/origin_filter.dart';
import '../core/recent_searches.dart';
import '../core/stores.dart';
import '../ui/nav.dart';
import '../ui/shell.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _fieldFocus = FocusNode();
  final RecentSearchesStore _recents = AppServices.instance.recentSearches;
  late final AppSettings _settings;
  Timer? _debounce;

  List<MediaItem> _results = const [];
  bool _loading = false;
  bool _searched = false;
  String? _error;
  String _lastQuery = '';
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _settings = AppServices.instance.settings;
    AppEvents.searchFocusTick.addListener(_focusField);
    AppEvents.refreshTick.addListener(_onRefreshTick);
  }

  @override
  void dispose() {
    _generation += 1;
    _debounce?.cancel();
    AppEvents.searchFocusTick.removeListener(_focusField);
    AppEvents.refreshTick.removeListener(_onRefreshTick);
    _controller.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  void _focusField() {
    if (mounted) _fieldFocus.requestFocus();
  }

  void _onRefreshTick() {
    if (!mounted) return;
    if (_lastQuery.isNotEmpty && _controller.text.trim() == _lastQuery) {
      _search();
    }
  }

  /// Debounced typing searches without remembering the term; only an explicit
  /// action (Enter, the search glyph, or a recent chip) fills the history.
  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      _generation += 1;
      setState(() {
        _results = const [];
        _searched = false;
        _loading = false;
        _error = null;
        _lastQuery = '';
      });
      return;
    }
    // The clear-icon suffix depends on the text, so repaint as it changes.
    setState(() {});
    _debounce = Timer(const Duration(milliseconds: 350), _search);
  }

  Future<void> _search({bool remember = false}) async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    final generation = ++_generation;
    _debounce?.cancel();
    if (remember) {
      unawaited(_recents.record(query));
    }
    setState(() {
      _loading = true;
      _error = null;
      _lastQuery = query;
    });
    try {
      final results = await ApiClient.instance.search(query);
      if (!mounted || generation != _generation) return;
      setState(() {
        _results = results;
        _loading = false;
        _searched = true;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = error.toString();
        _searched = true;
      });
    }
  }

  void _runRecent(String term) {
    _controller.text = term;
    _controller.selection = TextSelection.collapsed(
      offset: _controller.text.length,
    );
    _search(remember: true);
  }

  void _clearInput() {
    _controller.clear();
    _onChanged('');
  }

  void _goBack() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    ShellScope.of(context).selectTab(AppTab.home);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: Listenable.merge([_settings, _recents]),
        builder: (context, _) {
          final visibleResults = _visibleResults(_settings);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    AppFocusable(
                      onTap: _goBack,
                      borderRadius: 999,
                      focusScale: 1.08,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: context.palette.card,
                          shape: BoxShape.circle,
                          border: Border.all(color: context.palette.stroke),
                        ),
                        child: const Directionality(
                          textDirection: TextDirection.ltr,
                          child: Icon(Icons.arrow_forward_rounded, size: 20),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DpadTextField(
                        child: TextField(
                          controller: _controller,
                          focusNode: _fieldFocus,
                          textInputAction: TextInputAction.search,
                          onChanged: _onChanged,
                          onSubmitted: (_) => _search(remember: true),
                          style: Theme.of(context).textTheme.bodyLarge,
                          decoration: InputDecoration(
                            hintText: 'جست‌وجو در فیلم‌ها و سریال‌ها…',
                            prefixIcon: IconButton(
                              tooltip: 'جست‌وجو',
                              onPressed: () => _search(remember: true),
                              icon: const Icon(Icons.search_rounded),
                            ),
                            suffixIcon: _controller.text.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: 'پاک کردن',
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 19,
                                    ),
                                    onPressed: _clearInput,
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _loading
                    ? const LoadingView(message: 'در حال جست‌وجو…')
                    : _error != null
                    ? ErrorView(message: _error!, onRetry: _search)
                    : !_searched
                    ? _idleView(context)
                    : visibleResults.isEmpty
                    ? const EmptyView(
                        message: 'نتیجه‌ای پیدا نشد.',
                        icon: Icons.search_off_rounded,
                      )
                    : PosterGrid(
                        items: visibleResults,
                        maxExtent: width >= 760 ? 180 : 150,
                        onOpen: (item) =>
                            Navigator.of(context)
                                .push(appRoute(DetailScreen(item: item))),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Origin/anime hiding applies to search results too, like the macOS app.
  List<MediaItem> _visibleResults(AppSettings settings) {
    final hiding = ContentHiding(
      origins: settings.hideRegionalOrigins,
      anime: settings.hideAnime,
    );
    return _results.where((item) => !hiding.isHidden(item)).toList();
  }

  Widget _idleView(BuildContext context) {
    final terms = _recents.terms;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (terms.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
            child: Row(
              children: [
                Text(
                  'جستجوهای اخیر',
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: context.palette.textSecondary,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _recents.clear,
                  child: const Text('پاک کردن'),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: terms.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) => _RecentChip(
                label: terms[index],
                onTap: () => _runRecent(terms[index]),
              ),
            ),
          ),
        ],
        const Expanded(
          child: EmptyView(
            message:
                'نام فیلم یا سریال را بنویسید تا نتایج اینجا نمایش داده شود.',
            icon: Icons.manage_search_rounded,
          ),
        ),
      ],
    );
  }
}

class _RecentChip extends StatelessWidget {
  const _RecentChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppFocusable(
      onTap: onTap,
      borderRadius: 999,
      focusScale: 1.03,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: context.palette.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: context.palette.stroke),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history_rounded,
              size: 15,
              color: context.palette.textTertiary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: context.palette.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
