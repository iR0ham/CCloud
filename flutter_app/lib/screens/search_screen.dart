import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/models.dart';
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
  Timer? _debounce;

  List<MediaItem> _results = const [];
  bool _loading = false;
  bool _searched = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _results = const [];
        _searched = false;
        _loading = false;
        _error = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), _search);
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await ApiClient.instance.search(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
        _searched = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
        _searched = true;
      });
    }
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
      child: Column(
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
                      onSubmitted: (_) => _search(),
                      style: Theme.of(context).textTheme.bodyLarge,
                      decoration: InputDecoration(
                        hintText: 'جست‌وجو در فیلم‌ها و سریال‌ها…',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _controller.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close_rounded, size: 19),
                                onPressed: () {
                                  _controller.clear();
                                  _onChanged('');
                                },
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
                        ? const EmptyView(
                            message:
                                'نام فیلم یا سریال را بنویسید تا نتایج اینجا نمایش داده شود.',
                            icon: Icons.manage_search_rounded,
                          )
                        : _results.isEmpty
                            ? const EmptyView(
                                message: 'نتیجه‌ای پیدا نشد.',
                                icon: Icons.search_off_rounded,
                              )
                            : PosterGrid(
                                items: _results,
                                maxExtent: width >= 760 ? 180 : 150,
                                onOpen: (item) => Navigator.of(context)
                                    .push(appRoute(DetailScreen(item: item))),
                                padding: const EdgeInsets.fromLTRB(
                                    16, 8, 16, 30),
                              ),
          ),
        ],
      ),
    );
  }
}
