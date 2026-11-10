import 'models.dart';

/// Everything the player needs for one play, plus the following episodes of a series.
class PlayerArgs {
  PlayerArgs({
    required this.title,
    this.subtitle,
    this.posterUrl,
    required this.sources,
    this.preferredSourceId,
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
      subtitle:
          [item.yearText, item.genreText].where((e) => e.isNotEmpty).join(' • '),
      posterUrl: item.image,
      sources: sources,
      preferredSourceId: sources.isEmpty ? null : sources.first.id,
      media: item,
    );
  }

  factory PlayerArgs.forEpisode(MediaItem series, Season season, Episode episode) {
    PlayerArgs build(Episode ep) => PlayerArgs(
          title: series.title,
          subtitle: '${season.title} • ${ep.title}',
          posterUrl: series.image,
          sources: ep.playableSources,
          preferredSourceId:
              ep.playableSources.isEmpty ? null : ep.playableSources.first.id,
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

  factory PlayerArgs.forChannel(LiveTvChannel channel, String countryName) {
    final urls = channel.streams;
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
      sources.add(MediaSource(
        id: i + 1,
        quality: urls.length > 1
            ? (i == 0 ? 'منبع اصلی' : 'منبع ${faDigits(i + 1)}')
            : 'کیفیت اصلی',
        type: type,
        url: url,
      ));
    }
    return PlayerArgs(
      title: channel.name,
      subtitle: 'پخش زنده • $countryName',
      sources: sources,
      preferredSourceId: sources.isEmpty ? null : sources.first.id,
    );
  }
}
