import 'models.dart';

/// Playback menu label, matching Swift's `%.2g` formatting: whole speeds print
/// as `1x`, 0.75 prints `0.75x` and 1.25 prints `1.2x`.
String speedLabel(double value) {
  if ((value - value.roundToDouble()).abs() < 0.001) {
    return '${value.round()}x';
  }
  final scaled = value < 1
      ? _roundHalfEven(value * 100) / 100
      : _roundHalfEven(value * 10) / 10;
  var text = scaled.toStringAsFixed(2);
  text = text.replaceFirst(RegExp(r'0+$'), '');
  if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  return '${text}x';
}

int _roundHalfEven(double value) {
  final floor = value.floor();
  if ((value - floor - 0.5).abs() < 0.0000001) {
    return floor.isEven ? floor : floor + 1;
  }
  return value.round();
}

/// Label for an alternate audio track: Persian language name when known, then
/// the track's own title, then «صدای N».
String audioTrackLabel({
  String? title,
  String? language,
  required int ordinal,
}) {
  final code = (language ?? '').toLowerCase().split(RegExp(r'[-_ ]')).first;
  if (code.isNotEmpty) {
    final persian = persianLiveLanguage(code);
    if (persian != code) return persian;
  }
  if (title != null && title.trim().isNotEmpty) return title;
  return 'صدای ${faDigits(ordinal + 1)}';
}

/// Episode label used by the series play button and Continue Watching,
/// matching the macOS `episodeLabel`: «قسمت N» for numbered episodes, the
/// episode's own title otherwise.
String episodeLabelText(Episode episode) {
  final number = episode.episodeNumber;
  return number != null ? 'قسمت ${faDigits(number)}' : episode.title;
}

/// Everything the player needs for one play, plus the following episodes of a series.
class PlayerArgs {
  PlayerArgs({
    required this.title,
    this.subtitle,
    this.posterUrl,
    required this.sources,
    this.preferredSourceId,
    this.honorPreferredSource = false,
    this.media,
    this.episodeId,
    this.seasonTitle,
    this.episodeLabel,
    List<PlayerArgs>? upcoming,
  }) : upcoming = upcoming ?? const [];

  final String title;
  final String? subtitle;
  final String? posterUrl;
  final List<MediaSource> sources;
  final int? preferredSourceId;

  /// An explicit source pick (a quality row on the detail page) wins even when
  /// the user has a preferred-quality setting; the automatic play button keeps
  /// honouring that setting.
  final bool honorPreferredSource;
  final MediaItem? media;
  final int? episodeId;
  final String? seasonTitle;
  final String? episodeLabel;
  final List<PlayerArgs> upcoming;

  bool get isLive => subtitle?.contains('پخش زنده') ?? false;

  PlayerArgs advance() {
    final nextArgs = upcoming.first;
    return PlayerArgs(
      title: nextArgs.title,
      subtitle: nextArgs.subtitle,
      posterUrl: nextArgs.posterUrl ?? posterUrl,
      sources: nextArgs.sources,
      preferredSourceId: nextArgs.preferredSourceId,
      honorPreferredSource: nextArgs.honorPreferredSource,
      media: nextArgs.media ?? media,
      episodeId: nextArgs.episodeId,
      seasonTitle: nextArgs.seasonTitle,
      episodeLabel: nextArgs.episodeLabel,
      upcoming: upcoming.sublist(1),
    );
  }

  factory PlayerArgs.forMovie(MediaItem item) {
    final sources = item.playableSources;
    return PlayerArgs(
      title: item.title,
      subtitle: [
        item.yearText,
        item.genreText,
      ].where((e) => e.isNotEmpty).join(' • '),
      posterUrl: item.image,
      sources: sources,
      preferredSourceId: sources.isEmpty ? null : sources.first.id,
      media: item,
    );
  }

  factory PlayerArgs.forEpisode(
    MediaItem series,
    Season season,
    Episode episode,
  ) {
    PlayerArgs build(Episode ep) => PlayerArgs(
      title: series.title,
      subtitle: '${season.title} • ${ep.title}',
      posterUrl: series.image,
      sources: ep.playableSources,
      preferredSourceId: ep.playableSources.isEmpty
          ? null
          : ep.playableSources.first.id,
      media: series,
      episodeId: ep.id,
      seasonTitle: season.title,
      episodeLabel: ep.title,
    );

    final index = season.episodes.indexWhere((e) => e.id == episode.id);
    final following = index < 0
        ? const <Episode>[]
        : season.episodes.skip(index + 1).toList();

    return PlayerArgs(
      title: series.title,
      subtitle: '${season.title} • ${episode.title}',
      posterUrl: series.image,
      sources: episode.playableSources,
      preferredSourceId: episode.playableSources.isEmpty
          ? null
          : episode.playableSources.first.id,
      media: series,
      episodeId: episode.id,
      seasonTitle: season.title,
      episodeLabel: episode.title,
      upcoming: following.map(build).toList(),
    );
  }

  factory PlayerArgs.forChannel(
    LiveTvChannel channel,
    String countryName, {
    String? streamOverride,
  }) {
    final urls = streamOverride != null ? [streamOverride] : channel.streams;
    final sources = <MediaSource>[];
    for (var i = 0; i < urls.length; i++) {
      final url = urls[i];
      final lower = url.toLowerCase();
      final type = lower.contains('.m3u8')
          ? 'm3u8'
          : lower.contains('.mp4')
          ? 'mp4'
          : lower.contains('.mpd')
          ? 'mpd'
          : 'hls';
      sources.add(
        MediaSource(
          id: i + 1,
          quality: urls.length > 1
              ? (i == 0 ? 'منبع اصلی' : 'منبع ${faDigits(i + 1)}')
              : 'کیفیت اصلی',
          type: type,
          url: url,
        ),
      );
    }
    return PlayerArgs(
      title: channel.name,
      subtitle: 'پخش زنده • $countryName',
      sources: sources,
      preferredSourceId: sources.isEmpty ? null : sources.first.id,
    );
  }
}

/// Source the player opens first.
///
/// An explicit pick (the detail page's quality rows) wins over the saved
/// preferred quality; otherwise the automatic play button keeps honouring it,
/// matching the macOS source walk.
MediaSource? pickPlaybackSource(PlayerArgs args, String preferredQuality) {
  final playable = args.sources
      .where((source) => source.url.isNotEmpty && !source.isTrailer)
      .toList();
  if (playable.isEmpty) return null;
  final preferredId = args.preferredSourceId;
  if (preferredId != null) {
    for (final source in playable) {
      if (source.id == preferredId &&
          (args.honorPreferredSource || preferredQuality == 'auto')) {
        return source;
      }
    }
  }
  return preferredSource(playable, preferredQuality) ?? playable.first;
}
