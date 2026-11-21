import 'package:ccloud/core/models.dart';
import 'package:ccloud/core/playback.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sources = [
    MediaSource(id: 1, quality: '1080p', type: 'mp4', url: 'https://x/1.mp4'),
    MediaSource(id: 2, quality: '720p', type: 'mp4', url: 'https://x/2.mp4'),
    MediaSource(id: 3, quality: '480p', type: 'mp4', url: 'https://x/3.mp4'),
  ];

  test('an explicit pick wins over the preferred-quality setting', () {
    final args = PlayerArgs(
      title: 't',
      sources: sources,
      preferredSourceId: 3,
      honorPreferredSource: true,
    );
    expect(pickPlaybackSource(args, '1080p')?.id, 3);
    expect(pickPlaybackSource(args, 'auto')?.id, 3);
  });

  test('automatic play still honours the preferred-quality setting', () {
    final args = PlayerArgs(title: 't', sources: sources, preferredSourceId: 1);
    expect(pickPlaybackSource(args, '720p')?.id, 2);
  });

  test('trailers and empty urls are never picked', () {
    final args = PlayerArgs(
      title: 't',
      sources: const [
        MediaSource(
          id: 1,
          quality: 'تیزر',
          type: 'mp4',
          url: 'https://x/trailer.mp4',
        ),
        MediaSource(id: 2, quality: '1080p', type: 'mp4', url: ''),
        MediaSource(id: 3, quality: '720p', type: 'mp4', url: 'https://x/a'),
      ],
    );
    expect(pickPlaybackSource(args, 'auto')?.id, 3);
  });
}
