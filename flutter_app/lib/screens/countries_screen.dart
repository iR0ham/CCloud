import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../ui/nav.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'browse_screen.dart';

class CountriesScreen extends StatefulWidget {
  const CountriesScreen({super.key});

  @override
  State<CountriesScreen> createState() => _CountriesScreenState();
}

class _CountriesScreenState extends State<CountriesScreen> {
  final TextEditingController _search = TextEditingController();
  List<Country> _countries = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final countries = await ApiClient.instance.countries();
      if (!mounted) return;
      setState(() {
        _countries = countries;
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

  List<Country> get _filtered {
    final query = _search.text.trim();
    if (query.isEmpty) return _countries;
    return _countries
        .where((country) => country.title.contains(query))
        .toList();
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
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('کشورها',
                    style: Theme.of(context).textTheme.headlineMedium),
                Text('فیلم و سریال هر کشور',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 10),
                DpadTextField(
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: 'جست‌وجوی کشور…',
                      prefixIcon: Icon(Icons.public_rounded),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const LoadingView(message: 'در حال دریافت کشورها…')
                : _error != null
                    ? ErrorView(message: _error!, onRetry: _load)
                    : _filtered.isEmpty
                        ? const EmptyView(
                            message: 'کشوری پیدا نشد.',
                            icon: Icons.public_off_rounded,
                          )
                        : GridView.builder(
                            padding:
                                const EdgeInsets.fromLTRB(16, 12, 16, 30),
                            gridDelegate:
                                SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: width >= 760 ? 190 : 130,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 1.55,
                            ),
                            itemCount: _filtered.length,
                            itemBuilder: (context, index) {
                              final country = _filtered[index];
                              return _CountryCard(
                                country: country,
                                onTap: () => Navigator.of(context).push(
                                  appRoute(
                                      CountryBrowseScreen(country: country)),
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

class _CountryCard extends StatelessWidget {
  const _CountryCard({required this.country, required this.onTap});

  final Country country;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final imageUrl = ApiClient.instance.imageUrl(country.image);
    return AppFocusable(
      onTap: onTap,
      borderRadius: AppRadii.normal,
      focusScale: 1.03,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadii.normal),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl != null)
              AsyncImage(url: imageUrl)
            else
              Container(color: context.palette.card),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.78),
                    Colors.black.withValues(alpha: 0.1),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 10,
              bottom: 8,
              left: 10,
              child: Text(
                country.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
