import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/connectivity.dart';
import '../core/platform_info.dart';
import '../screens/browse_screen.dart';
import '../screens/categories_screen.dart';
import '../screens/countries_screen.dart';
import '../screens/favorites_screen.dart';
import '../screens/history_screen.dart';
import '../screens/home_screen.dart';
import '../screens/live_screen.dart';
import '../screens/search_screen.dart';
import '../screens/settings_screen.dart';
import 'theme.dart';
import 'widgets.dart';

enum AppTab {
  home('خانه', Icons.home_rounded),
  movies('فیلم‌ها', Icons.local_movies_rounded),
  series('سریال‌ها', Icons.live_tv_rounded),
  live('پخش زنده', Icons.sensors_rounded),
  search('جست‌وجو', Icons.search_rounded),
  categories('دسته‌بندی‌ها', Icons.grid_view_rounded),
  countries('کشورها', Icons.public_rounded),
  favorites('علاقه‌مندی‌ها', Icons.favorite_rounded),
  history('اخیراً دیده‌شده', Icons.history_rounded),
  settings('تنظیمات', Icons.settings_rounded);

  const AppTab(this.title, this.icon);

  final String title;
  final IconData icon;
}

/// Lets descendants (home rails, empty states) switch the active tab.
class ShellScope extends InheritedWidget {
  const ShellScope({super.key, required this.selectTab, required super.child});

  final ValueChanged<AppTab> selectTab;

  static ShellScope of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ShellScope>();
    assert(scope != null, 'ShellScope is missing above this context');
    return scope!;
  }

  @override
  bool updateShouldNotify(ShellScope oldWidget) => false;
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppTab _tab = AppTab.home;
  final Map<AppTab, Widget> _pages = {};
  final Map<AppTab, FocusNode> _tabFocus = {};

  late final ConnectivityState _connectivity;
  bool _wasOffline = false;

  @override
  void initState() {
    super.initState();
    _connectivity = ApiClient.instance.connectivity;
    _connectivity.addListener(_onConnectivityChanged);
    _wasOffline = _connectivity.isOffline;
    if (_connectivity.isOffline) {
      // The first load already fell back to the disk copy; still tell the user
      // once, as the macOS app does on connect failure.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showConnectivityToast(offline: true);
      });
    }
  }

  @override
  void dispose() {
    _connectivity.removeListener(_onConnectivityChanged);
    for (final node in _tabFocus.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// Toasts only on a real transition, like the macOS app: telling the user
  /// on every request would be noise.
  void _onConnectivityChanged() {
    final offline = _connectivity.isOffline;
    if (offline == _wasOffline) return;
    _wasOffline = offline;
    _showConnectivityToast(offline: offline);
  }

  void _showConnectivityToast({required bool offline}) {
    final message = offline
        ? 'اتصال به سرور برقرار نشد؛ محتوای ذخیره‌شده نمایش داده می‌شود'
        : 'اتصال به سرور برقرار شد';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(milliseconds: 2200),
        ),
      );
    });
  }

  FocusNode _tabFocusNode(AppTab tab) => _tabFocus.putIfAbsent(
    tab,
    () => FocusNode(debugLabel: 'tab-${tab.name}'),
  );

  Widget _pageFor(AppTab tab) {
    final page = _pages.putIfAbsent(tab, () {
      switch (tab) {
        case AppTab.home:
          return const HomeScreen();
        case AppTab.movies:
          return const BrowseScreen(kind: BrowseKind.movies);
        case AppTab.series:
          return const BrowseScreen(kind: BrowseKind.series);
        case AppTab.live:
          return const LiveScreen();
        case AppTab.search:
          return const SearchScreen();
        case AppTab.categories:
          return const CategoriesScreen();
        case AppTab.countries:
          return const CountriesScreen();
        case AppTab.favorites:
          return const FavoritesScreen();
        case AppTab.history:
          return const HistoryScreen();
        case AppTab.settings:
          return const SettingsScreen();
      }
    });
    return Focus(
      focusNode: _tabFocusNode(tab),
      // The wrapper is only a parking spot for programmatic focus moves; it
      // must never be a D-pad candidate or focus appears to vanish.
      skipTraversal: true,
      includeSemantics: false,
      child: page,
    );
  }

  void _select(AppTab tab) {
    // When the switch comes from a rail item, that item keeps focus and the
    // next D-pad press walks into the page. Programmatic switches (see-all
    // links, back-to-home) must move focus off the now-hidden page instead.
    final fromPage = _tabFocus.values.any((node) => node.hasFocus);
    setState(() => _tab = tab);
    if (PlatformInfo.isTv && fromPage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _tabFocusNode(tab).requestFocus();
      });
    }
  }

  void _popToHome() {
    _select(AppTab.home);
    if (PlatformInfo.isTv) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _tabFocusNode(AppTab.home).requestFocus();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = PlatformInfo.isTv || MediaQuery.sizeOf(context).width >= 760;
    final palette = context.palette;

    final body = IndexedStack(
      index: _tab.index,
      sizing: StackFit.expand,
      children: AppTab.values.map((tab) {
        if (_pages.containsKey(tab) || tab == _tab) {
          // Hidden stack children are laid out and stay in the focus tree, so
          // D-pad focus can wander into invisible pages. Keep them out.
          return ExcludeFocus(excluding: tab != _tab, child: _pageFor(tab));
        }
        return const SizedBox.shrink();
      }).toList(),
    );

    if (wide) {
      return ShellScope(
        selectTab: _select,
        child: PopScope(
          canPop: _tab == AppTab.home,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _popToHome();
          },
          child: Scaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            body: Row(
              children: [
                _SideRail(selected: _tab, onSelect: _select),
                VerticalDivider(width: 1, color: palette.stroke),
                Expanded(child: body),
              ],
            ),
          ),
        ),
      );
    }

    const bottomTabs = [AppTab.home, AppTab.movies, AppTab.series, AppTab.live];
    final bottomIndex = bottomTabs.contains(_tab)
        ? bottomTabs.indexOf(_tab)
        : 4;

    return ShellScope(
      selectTab: _select,
      child: PopScope(
        canPop: _tab == AppTab.home,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _popToHome();
        },
        child: Scaffold(
          body: body,
          bottomNavigationBar: NavigationBar(
            selectedIndex: bottomIndex,
            height: 66,
            onDestinationSelected: (index) {
              if (index < bottomTabs.length) {
                _select(bottomTabs[index]);
              } else {
                _openMoreSheet();
              }
            },
            destinations: [
              for (final tab in bottomTabs)
                NavigationDestination(icon: Icon(tab.icon), label: tab.title),
              const NavigationDestination(
                icon: Icon(Icons.menu_rounded),
                label: 'بیشتر',
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openMoreSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            children: [
              for (final tab in [
                AppTab.search,
                AppTab.categories,
                AppTab.countries,
                AppTab.favorites,
                AppTab.history,
                AppTab.settings,
              ])
                AppFocusable(
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _select(tab);
                  },
                  borderRadius: AppRadii.normal,
                  focusScale: 1.01,
                  child: ListTile(
                    leading: Icon(tab.icon),
                    title: Text(tab.title),
                    trailing: const Icon(Icons.chevron_left_rounded),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SideRail extends StatelessWidget {
  const _SideRail({required this.selected, required this.onSelect});

  final AppTab selected;
  final ValueChanged<AppTab> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final compact = MediaQuery.sizeOf(context).width < 1000;
    return Container(
      width: compact ? 210 : 236,
      color: palette.sidebar,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
              child: Row(
                children: [
                  Image.asset(
                    context.isDark ? 'assets/logo-dark.png' : 'assets/logo.png',
                    width: 36,
                    height: 36,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.cloud_rounded,
                      color: AppColors.accent,
                      size: 34,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CCloud',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 2),
                        const _ConnectionBadge(),
                        Text(
                          'نسخه اندروید',
                          style: TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: 10,
                            color: palette.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  for (final tab in AppTab.values)
                    if (tab != AppTab.settings)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: _RailItem(
                          tab: tab,
                          selected: selected == tab,
                          autofocus: PlatformInfo.isTv && tab == AppTab.home,
                          onTap: () => onSelect(tab),
                        ),
                      ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: _RailItem(
                tab: AppTab.settings,
                selected: selected == AppTab.settings,
                onTap: () => onSelect(AppTab.settings),
              ),
            ),
            const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }
}

/// Dot + host under the app name: gold when content comes from the offline
/// copy, red when a request failed with nothing cached, green otherwise.
class _ConnectionBadge extends StatelessWidget {
  const _ConnectionBadge();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ApiClient.instance.connectivity,
      builder: (context, _) {
        final connectivity = ApiClient.instance.connectivity;
        final offline = connectivity.isOffline;
        final failed = connectivity.hasError;
        final color = offline
            ? AppColors.gold
            : failed
            ? AppColors.red
            : AppColors.green;
        final text = offline
            ? 'آفلاین • ${connectivity.host}'
            : connectivity.host;
        return Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: offline
                      ? AppColors.gold
                      : context.palette.textSecondary,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.tab,
    required this.selected,
    required this.onTap,
    this.autofocus = false,
  });

  final AppTab tab;
  final bool selected;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return AppFocusable(
      onTap: onTap,
      autofocus: autofocus,
      borderRadius: 9,
      focusScale: 1.01,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          children: [
            Icon(
              tab.icon,
              size: 18,
              color: selected ? Colors.white : palette.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                tab.title,
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? Colors.white : palette.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
