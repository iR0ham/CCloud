import 'package:flutter/material.dart';

import '../core/catalogue.dart';
import '../core/models.dart';
import '../ui/nav.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'browse_screen.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key});

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  List<Genre> _genres = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final genres = await Catalogue.genres();
      if (!mounted) return;
      setState(() {
        _genres = genres;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('دسته‌بندی‌ها',
                    style: Theme.of(context).textTheme.headlineMedium),
                Text('بر اساس ژانر مرور کنید',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const LoadingView(message: 'در حال دریافت ژانرها…')
                : _error != null
                    ? ErrorView(message: _error!, onRetry: _load)
                    : GridView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 30),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 220,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 2.6,
                        ),
                        itemCount: _genres.length,
                        itemBuilder: (context, index) {
                          final genre = _genres[index];
                          return AppFocusable(
                            onTap: () => Navigator.of(context).push(
                              appRoute(GenreBrowseScreen(genre: genre)),
                            ),
                            borderRadius: AppRadii.normal,
                            focusScale: 1.02,
                            child: Container(
                              alignment: Alignment.center,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: context.palette.card,
                                borderRadius:
                                    BorderRadius.circular(AppRadii.normal),
                                border:
                                    Border.all(color: context.palette.stroke),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.grid_view_rounded,
                                      size: 17, color: AppColors.accentBright),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Text(
                                      genre.title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyLarge,
                                    ),
                                  ),
                                  Icon(Icons.chevron_left_rounded,
                                      size: 18,
                                      color: context.palette.textTertiary),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
