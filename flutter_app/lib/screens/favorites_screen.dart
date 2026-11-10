import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/stores.dart';
import '../ui/nav.dart';
import '../ui/widgets.dart';
import 'detail_screen.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  int _filter = 0; // 0 all, 1 movies, 2 series

  @override
  Widget build(BuildContext context) {
    final favorites = AppServices.instance.favorites;
    return SafeArea(
      bottom: false,
      child: ListenableBuilder(
        listenable: favorites,
        builder: (context, _) {
          final entries = favorites.entries.where((entry) {
            if (_filter == 1) return !entry.isSeries;
            if (_filter == 2) return entry.isSeries;
            return true;
          }).toList();
          final items = entries.map((entry) => entry.item).toList();
          final width = MediaQuery.sizeOf(context).width;

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('علاقه‌مندی‌ها',
                        style: Theme.of(context).textTheme.headlineMedium),
                    Text(
                      '${faDigits(favorites.entries.length)} عنوان ذخیره‌شده',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
                child: FilterPills(
                  values: const [0, 1, 2],
                  selected: _filter,
                  labelBuilder: (value) => switch (value) {
                    1 => 'فیلم‌ها',
                    2 => 'سریال‌ها',
                    _ => 'همه',
                  },
                  onSelected: (value) => setState(() => _filter = value),
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? EmptyView(
                        message: favorites.entries.isEmpty
                            ? 'هنوز چیزی به علاقه‌مندی‌ها اضافه نکرده‌اید.'
                            : 'در این بخش چیزی ذخیره نشده است.',
                        icon: Icons.favorite_border_rounded,
                      )
                    : PosterGrid(
                        items: items,
                        maxExtent: width >= 760 ? 180 : 150,
                        onOpen: (item) => Navigator.of(context)
                            .push(appRoute(DetailScreen(item: item))),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
