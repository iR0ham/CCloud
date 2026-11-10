import 'package:flutter/material.dart';

import '../core/live_tv_client.dart';
import '../core/models.dart';
import '../core/playback.dart';
import '../ui/nav.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'player_screen.dart';

class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  final TextEditingController _countrySearch = TextEditingController();
  List<LiveTvCountry> _countries = const [];
  LiveTvCountry? _selected;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _countrySearch.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final countries = await LiveTvClient.instance.countries();
      if (!mounted) return;
      setState(() {
        _countries = countries;
        _selected ??= countries.firstWhere(
          (country) => country.code == 'IR',
          orElse: () => countries.first,
        );
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

  List<LiveTvCountry> get _filteredCountries {
    final query = _countrySearch.text.trim();
    if (query.isEmpty) return _countries;
    return _countries
        .where(
          (country) =>
              country.persianName.contains(query) ||
              country.englishName.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 760;

    if (_loading) {
      return const LoadingView(message: 'در حال دریافت شبکه‌های زنده…');
    }
    if (_error != null) {
      return ErrorView(message: _error!, onRetry: _load);
    }

    if (!wide) {
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
                  Text(
                    'پخش زنده',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  Text(
                    'شبکه‌های تلویزیونی از سراسر جهان',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  TvSearchField(
                    controller: _countrySearch,
                    onChanged: (_) => setState(() {}),
                    hintText: 'جست‌وجوی کشور…',
                    icon: Icons.public_rounded,
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
                children: [
                  for (final country in _filteredCountries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _CountryTile(
                        country: country,
                        onTap: () => Navigator.of(
                          context,
                        ).push(appRoute(LiveChannelsScreen(country: country))),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final selected = _selected;
    return SafeArea(
      bottom: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 260,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'پخش زنده',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      TvSearchField(
                        controller: _countrySearch,
                        onChanged: (_) => setState(() {}),
                        hintText: 'جست‌وجوی کشور…',
                        icon: Icons.public_rounded,
                        iconSize: 18,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 20),
                    itemCount: _filteredCountries.length,
                    itemBuilder: (context, index) {
                      final country = _filteredCountries[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: _CountryRow(
                          country: country,
                          selected: country.code == selected?.code,
                          onTap: () => setState(() => _selected = country),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          VerticalDivider(width: 1, color: context.palette.stroke),
          Expanded(
            child: selected == null
                ? const EmptyView(message: 'کشوری انتخاب نشده است.')
                : _ChannelsPane(
                    key: ValueKey(selected.code),
                    country: selected,
                  ),
          ),
        ],
      ),
    );
  }
}

class _ChannelsPane extends StatefulWidget {
  const _ChannelsPane({super.key, required this.country});

  final LiveTvCountry country;

  @override
  State<_ChannelsPane> createState() => _ChannelsPaneState();
}

class _ChannelsPaneState extends State<_ChannelsPane> {
  final TextEditingController _search = TextEditingController();
  List<LiveTvChannel> _channels = const [];
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
      final channels = await LiveTvClient.instance.channels(
        widget.country.code,
      );
      if (!mounted) return;
      setState(() {
        _channels = channels;
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

  List<LiveTvChannel> get _filtered {
    final query = _search.text.trim();
    if (query.isEmpty) return _channels;
    return _channels
        .where(
          (channel) => channel.name.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(
            children: [
              Text(widget.country.flag, style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.country.persianName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      '${faDigits(_channels.length)} شبکه',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 220,
                child: TvSearchField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  hintText: 'جست‌وجوی شبکه…',
                  icon: Icons.search_rounded,
                  iconSize: 19,
                  style: Theme.of(context).textTheme.bodyMedium,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const LoadingView(message: 'در حال دریافت شبکه‌ها…')
              : _error != null
              ? ErrorView(message: _error!, onRetry: _load)
              : _filtered.isEmpty
              ? const EmptyView(
                  message: 'شبکه‌ای پیدا نشد.',
                  icon: Icons.tv_off_rounded,
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                  itemCount: _filtered.length,
                  itemBuilder: (context, index) {
                    final channel = _filtered[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ChannelTile(
                        channel: channel,
                        countryName: widget.country.persianName,
                        autofocus: index == 0,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class LiveChannelsScreen extends StatelessWidget {
  const LiveChannelsScreen({super.key, required this.country});

  final LiveTvCountry country;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(country.persianName),
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
      body: _ChannelsPane(country: country),
    );
  }
}

class _CountryRow extends StatelessWidget {
  const _CountryRow({
    required this.country,
    required this.selected,
    required this.onTap,
  });

  final LiveTvCountry country;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppFocusable(
      onTap: onTap,
      borderRadius: 10,
      focusScale: 1.01,
      keepDirectionalWithinScrollable: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent
              : (context.palette.card.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Text(country.flag, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                country.persianName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? Colors.white
                      : context.palette.textSecondary,
                ),
              ),
            ),
            Text(
              faDigits(country.channelCount),
              style: TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 10.5,
                color: selected ? Colors.white70 : context.palette.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountryTile extends StatelessWidget {
  const _CountryTile({required this.country, required this.onTap});

  final LiveTvCountry country;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppFocusable(
      onTap: onTap,
      borderRadius: AppRadii.normal,
      focusScale: 1.01,
      keepDirectionalWithinScrollable: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: context.palette.card,
          borderRadius: BorderRadius.circular(AppRadii.normal),
          border: Border.all(color: context.palette.stroke),
        ),
        child: Row(
          children: [
            Text(country.flag, style: const TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    country.persianName,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  Text(
                    '${faDigits(country.channelCount)} شبکه',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_left_rounded,
              color: context.palette.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChannelMonogram extends StatelessWidget {
  const _ChannelMonogram({required this.name});

  final String name;

  static const _palette = [
    AppColors.accent,
    Color(0xFFE5484D),
    Color(0xFF30A46C),
    Color(0xFFF2A93B),
    Color(0xFF8E4EC6),
    Color(0xFF0091FF),
    Color(0xFFD6409E),
    Color(0xFF12A594),
  ];

  static const _genericWords = {
    'tv',
    'hd',
    'fhd',
    'uhd',
    'sd',
    'channel',
    'live',
    'شبکه',
    'تلویزیون',
    'پخش',
  };

  String get _letters {
    final raw = name.trim();
    final parts = raw.split(RegExp(r'[\s\-|·]+'));
    final meaningful = [
      for (final part in parts)
        if (part.trim().isNotEmpty &&
            !_genericWords.contains(part.trim().toLowerCase()))
          part.trim(),
    ];
    final String letters;
    if (meaningful.length >= 2) {
      letters = meaningful
          .take(2)
          .map((word) => String.fromCharCode(word.runes.first))
          .join();
    } else if (meaningful.length == 1) {
      letters = String.fromCharCodes(meaningful.first.runes.take(2));
    } else {
      letters = String.fromCharCodes(raw.runes.take(2));
    }
    return letters.isEmpty ? '•' : letters.toUpperCase();
  }

  Color get _tint {
    var hash = 5381;
    for (final unit in name.toLowerCase().codeUnits) {
      hash = ((hash << 5) + hash + unit) & 0x7fffffff;
    }
    return _palette[hash % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final tint = _tint;
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tint.withValues(alpha: 0.95), tint.withValues(alpha: 0.52)],
        ),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Text(
        _letters,
        maxLines: 1,
        textDirection: TextDirection.ltr,
        style: const TextStyle(
          fontFamily: AppTheme.fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    required this.channel,
    required this.countryName,
    this.autofocus = false,
  });

  final LiveTvChannel channel;
  final String countryName;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final hasStream = channel.streams.isNotEmpty;
    return AppFocusable(
      autofocus: autofocus,
      onTap: !hasStream
          ? () {}
          : () => Navigator.of(context).push(
              appRoute(
                PlayerScreen(args: PlayerArgs.forChannel(channel, countryName)),
              ),
            ),
      enabled: hasStream,
      borderRadius: AppRadii.normal,
      focusScale: 1.01,
      keepDirectionalWithinScrollable: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: context.palette.card,
          borderRadius: BorderRadius.circular(AppRadii.normal),
          border: Border.all(color: context.palette.stroke),
        ),
        child: Row(
          children: [
            _ChannelMonogram(name: channel.name),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    channel.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  Text(
                    channel.languageLabel,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (channel.isGeoBlocked)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: MetaChip(
                  label: 'محدود جغرافیایی',
                  icon: Icons.lock_outline,
                ),
              ),
            Icon(
              Icons.play_circle_outline_rounded,
              color: hasStream
                  ? AppColors.accentBright
                  : context.palette.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
