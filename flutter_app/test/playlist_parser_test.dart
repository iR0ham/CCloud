import 'dart:convert';
import 'dart:io';

import 'package:ccloud/core/identity_hash.dart';
import 'package:ccloud/core/live_contracts.dart';
import 'package:ccloud/core/playlist_parser.dart';
import 'package:ccloud/core/source_registry.dart';
import 'package:flutter_test/flutter_test.dart';

// Task B2-D. These fixtures are the shared bytes the Swift (`Tests/live-foundation/`) and
// webOS (`Tests/webos/`) parser suites read next, so every literal below is a cross-language
// expectation and not a Dart-only preference. A value is asserted against the *parsed* object
// rather than against encoded text, because Foundation escapes `/` as `\/` in JSON and no raw
// substring comparison can be port-neutral (proof: `Sources/Core/APIClient.swift:206`).
const _fixtureDir = '../Tests/fixtures/multi-source';

String _fixture(String name) =>
    File('$_fixtureDir/$name').readAsStringSync(encoding: utf8);

void main() {
  group('stableKeyHash', () {
    test('is deterministic, differs across inputs, and stays 32 lowercase hex', () {
      expect(stableKeyHash('same'), stableKeyHash('same'));
      expect(stableKeyHash('same') == stableKeyHash('different'), isFalse);
      expect(stableKeyHash('same'), matches(RegExp(r'^[0-9a-f]{32}$')));
      // The empty input is the one case a "hash the accumulated value" bug can hide in:
      // four zero seeds would render as `00000000...`, which no non-empty input may equal.
      expect(stableKeyHash(''), matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(stableKeyHash('') == stableKeyHash('same'), isFalse);
      // Non-ASCII must hash over UTF-8 bytes, not code units, or the Swift and JavaScript
      // ports would silently disagree on every Persian channel name.
      expect(stableKeyHash('پرس'), matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(stableKeyHash('پرس') == stableKeyHash('press'), isFalse);
    });

    test('reproduces the golden digests the other two ports pin', () {
      // These three literals are not Dart's own output. They are what the `macos-15` runner
      // printed for the Swift implementation (`Tests/live-foundation/main.swift` prints
      // `golden stableKeyHash(...) = ...`), and `Tests/webos/playlist_parser.test.js:162-164`
      // pins the identical strings. The shape checks above cannot notice a recipe drift —
      // FNV-1 instead of FNV-1a, a changed seed, a dropped mask — because all of those still
      // render as 32 lowercase hex. Pinning a foreign value is what makes a Dart-side drift
      // fail here instead of minting member ids no other port recognises.
      expect(stableKeyHash(''), '811c9dc59e3779b985ebca6bc2b2ae35');
      expect(stableKeyHash('playlist:valid'), '981a29df6c39c1531339e5c1aef7688f');
      expect(stableKeyHash('پرس'), 'e724bb8086a3208c85ff01962c8b8030');
    });

    test('separates the four passes so a single-pass bug is visible', () {
      // Each pass contributes eight digits, so a hash that only ran the first seed has eight
      // distinct leading and trailing halves only by accident. All four segments must be
      // non-zero and the whole value must not be eight digits repeated four times.
      final value = stableKeyHash('segment-check');
      final segments = RegExp(r'.{8}').allMatches(value).map((m) => m[0]!).toList();
      expect(segments.length, 4);
      expect(segments.toSet().length, 4, reason: 'hash segments collapsed: $value');
    });
  });

  group('parsePlaylist', () {
    test('valid fixture parses to the pinned channel set and metadata', () {
      final validText = _fixture('valid.m3u');
      final valid = parsePlaylist(playlistId: 'playlist:valid', text: validText);
      expect(valid.contentHash, stableKeyHash(validText));
      expect(valid.inputBytes, utf8.encode(validText).length);
      expect(valid.format, PlaylistFormat.m3uChannelList);
      expect(valid.truncated, isFalse);
      expect(valid.channels.length, 3);
      expect(valid.channels.first.providerChannelId, 'PressTV');
      expect(valid.channels.first.countryCode, 'IR');
      expect(valid.channels.first.streamUrls.length, 2);
      expect(valid.channels.first.logoUrl, 'https://img.example/press.png');
      expect(valid.channels.last.languages, isEmpty);
      // The quality suffix is stripped by the shared display-name rule, and the raw tvg-id
      // survives for identity work: both are contract points the ports must state.
      expect(valid.channels.first.displayName, 'Press TV');
      expect(valid.channels.first.tvgId, 'PressTV.ir');
      expect(valid.channels.first.line, 2);
      expect(valid.channels.last.providerChannelId, 'MusicTV');
      expect(valid.channels.last.streamUrls, ['https://music.example/live.m3u8']);
      // `tvg-language` is parsed, not invented: only the two rows that carry it get one.
      expect(valid.channels.first.languages, ['English']);
      expect(valid.channels.map((c) => c.countryCode), ['IR', 'IR', 'IR']);
      expect(valid.issues, isEmpty);
    });

    test('header-only input is empty without inventing issues', () {
      final empty = parsePlaylist(
        playlistId: 'playlist:empty',
        text: _fixture('empty.m3u'),
      );
      expect(empty.format, PlaylistFormat.empty);
      expect(empty.channels, isEmpty);
      expect(empty.issues, isEmpty);
      expect(empty.truncated, isFalse);
    });

    test('an HLS master manifest is classified, not parsed as channels', () {
      final hls = parsePlaylist(
        playlistId: 'playlist:hls',
        text: _fixture('hls-master.m3u8'),
      );
      expect(hls.format, PlaylistFormat.hlsMediaManifest);
      expect(hls.issues.single.code, 'unsupportedMediaManifest');
      expect(hls.channels, isEmpty);
    });

    test('malformed input keeps the one good row and reports all four codes', () {
      final malformed = parsePlaylist(
        playlistId: 'playlist:malformed',
        text: _fixture('malformed.m3u'),
      );
      expect(malformed.format, PlaylistFormat.m3uChannelList);
      expect(malformed.channels.single.displayName, 'Good TV');
      expect(
        malformed.issues.map((i) => i.code),
        containsAll(['missingName', 'missingStream', 'malformedEntry', 'invalidUrl']),
      );
      // Every issue names a physical line, because the UI has to say which row broke.
      expect(malformed.issues.every((i) => i.line != null && i.line! > 0), isTrue);
      // `invalidUrl` belongs to the row it came from, so a discarded entry cannot be the
      // retained one: exactly one channel survives.
      expect(malformed.channels.length, 1);
    });

    test('a missing provider id stays separate instead of collapsing into one row', () {
      // Identity rule 2: the fallback key carries an occurrence index, so two nameless-id
      // rows with the same name still register as two members.
      final text = '#EXTM3U\n'
          '#EXTINF:-1 ,Twin TV\nhttps://twin.example/a.m3u8\n'
          '#EXTINF:-1 ,Twin TV\nhttps://twin.example/b.m3u8\n';
      final parsed = parsePlaylist(playlistId: 'playlist:twin', text: text);
      expect(parsed.channels.length, 2);
      expect(parsed.channels.first.providerChannelId, isNot(parsed.channels.last.providerChannelId));
      expect(parsed.channels.first.providerChannelId, startsWith('fallback:'));
      final registry = registerParsedPlaylist(
        parsed: parsed,
        playlistId: 'playlist:twin',
        providerNamespace: 'fixture:provider',
      );
      expect(registry.members.length, 2);
      expect(registry.sources.length, 2);
      expect(registry.members.first.memberId, isNot(registry.members.last.memberId));
    });

    test('relative addresses resolve only against an HTTP(S) base', () {
      const text = '#EXTM3U\n#EXTINF:-1 tvg-id="Rel.ir",Rel TV\nstream.m3u8\n';
      final withoutBase = parsePlaylist(playlistId: 'playlist:rel', text: text);
      expect(withoutBase.channels, isEmpty);
      expect(withoutBase.issues.map((i) => i.code), contains('invalidUrl'));

      final withBase = parsePlaylist(
        playlistId: 'playlist:rel',
        text: text,
        baseUri: Uri.parse('https://cdn.example/live/index.m3u8'),
      );
      expect(
        withBase.channels.single.streamUrls.single,
        'https://cdn.example/live/stream.m3u8',
      );
      expect(withBase.issues, isEmpty);

      final fileBase = parsePlaylist(
        playlistId: 'playlist:rel',
        text: text,
        baseUri: Uri.parse('file:///tmp/index.m3u8'),
      );
      expect(fileBase.channels, isEmpty,
          reason: 'a local base must not smuggle a relative path into a playable URL');
      expect(fileBase.issues.map((i) => i.code), contains('invalidUrl'));
    });

    test('the 50,000-member ceiling truncates instead of failing the playlist', () {
      final rows = List.generate(
        50001,
        (i) => '#EXTINF:-1 tvg-id="C$i.ir",Channel $i\n'
            'https://cdn.example/$i.m3u8\n',
      ).join();
      final oversized = '#EXTM3U\n$rows';
      final limited = parsePlaylist(playlistId: 'playlist:large', text: oversized);
      expect(limited.channels.length, 50000);
      expect(limited.truncated, isTrue);
      expect(limited.issues.any((i) => i.code == 'limitExceeded'), isTrue);
    });

    test('the per-member URL ceiling keeps the first hundred addresses', () {
      final urls =
          List.generate(101, (i) => 'https://cdn.example/$i.m3u8').join('\n');
      final text =
          '#EXTM3U\n#EXTINF:-1 tvg-id="Many.ir",Many TV\n$urls\n';
      final parsed = parsePlaylist(playlistId: 'playlist:many', text: text);
      expect(parsed.channels.single.streamUrls.length, 100);
      expect(parsed.truncated, isTrue);
      expect(parsed.issues.map((i) => i.code), contains('limitExceeded'));
    });

    test('the physical line ceiling truncates a comment-heavy payload', () {
      final padding =
          List.generate(200001, (i) => '# pad $i').join('\n');
      final text =
          '#EXTM3U\n$padding\n#EXTINF:-1 tvg-id="Late.ir",Late TV\n'
          'https://cdn.example/late.m3u8\n';
      final parsed = parsePlaylist(playlistId: 'playlist:lines', text: text);
      expect(parsed.truncated, isTrue);
      expect(parsed.issues.map((i) => i.code), contains('limitExceeded'));
      expect(parsed.channels, isEmpty);
    });

    test('a payload over ten mebibytes is refused rather than parsed', () {
      final filler = 'x' * (10 * 1024 * 1024 + 16);
      final text = '#EXTM3U\n$filler';
      final parsed = parsePlaylist(playlistId: 'playlist:huge', text: text);
      expect(parsed.channels, isEmpty);
      expect(parsed.issues.map((i) => i.code), contains('oversizedInput'));
      expect(parsed.truncated, isTrue);
    });

    test('a document without #EXTM3U is invalid', () {
      final parsed = parsePlaylist(
        playlistId: 'playlist:none',
        text: 'https://cdn.example/orphan.m3u8\n',
      );
      expect(parsed.format, PlaylistFormat.invalid);
      expect(parsed.channels, isEmpty);
      expect(parsed.issues.map((i) => i.code), contains('malformedEntry'));
    });

    test('parsePlaylistAsync agrees with parsePlaylist for identical input', () async {
      final validText = _fixture('valid.m3u');
      final sync = parsePlaylist(playlistId: 'playlist:valid', text: validText);
      final async = await parsePlaylistAsync(
        playlistId: 'playlist:valid',
        text: validText,
      );
      expect(async.format, sync.format);
      expect(async.contentHash, sync.contentHash);
      expect(async.inputBytes, sync.inputBytes);
      expect(async.truncated, sync.truncated);
      expect(async.channels.length, sync.channels.length);
      for (var i = 0; i < sync.channels.length; i++) {
        expect(async.channels[i].providerChannelId, sync.channels[i].providerChannelId);
        expect(async.channels[i].displayName, sync.channels[i].displayName);
        expect(async.channels[i].streamUrls, sync.channels[i].streamUrls);
        expect(async.channels[i].line, sync.channels[i].line);
        expect(async.channels[i].logoUrl, sync.channels[i].logoUrl);
        expect(async.channels[i].group, sync.channels[i].group);
        expect(async.channels[i].countryCode, sync.channels[i].countryCode);
        expect(async.channels[i].languages, sync.channels[i].languages);
        expect(async.channels[i].tvgId, sync.channels[i].tvgId);
      }
      expect(async.issues.map((i) => i.code), sync.issues.map((i) => i.code));
    });
  });

  group('registerParsedPlaylist', () {
    test('duplicates merge into two members with the pinned priorities', () {
      final registry = registerParsedPlaylist(
        parsed: parsePlaylist(
          playlistId: 'playlist:duplicates',
          text: _fixture('duplicates.m3u'),
        ),
        playlistId: 'playlist:duplicates',
        providerNamespace: 'fixture:provider',
      );
      expect(registry.members.length, 2);
      expect(registry.sources.length, 3);
      expect(registry.sources.map((s) => s.priority).toList(), [0, 1, 0]);
      expect(
        registry.sources.every((s) => s.health == SourceHealth.unverified),
        isTrue,
      );
      expect(
        registry.sources.every((s) => s.rendererCapability == 'Not Yet Verified'),
        isTrue,
      );
      expect(
        registry.sources.every((s) => !s.sourceId.contains('https://')),
        isTrue,
      );
      // Identity rules 1 and 3, spelled out: the ports will paste these exact seeds.
      expect(
        registry.members.first.memberId,
        'member:${stableKeyHash('playlist:duplicates\nprovider\nfixture:provider\nDup')}',
      );
      expect(
        registry.sources.first.sourceId,
        'source:${stableKeyHash('${registry.members.first.memberId}\nurl\nhttps://dup.example/a.m3u8')}',
      );
      expect(registry.sources.first.channelId, registry.members.first.memberId);
      expect(registry.sources.first.memberId, registry.members.first.memberId);
      expect(registry.sources.first.playlistId, 'playlist:duplicates');
      expect(registry.sources.first.providerNamespace, 'fixture:provider');
      expect(registry.sources.first.origin, SourceOrigin.playlist);
      expect(registry.sources.first.enabled, isTrue);
      expect(registry.sources.first.streamUrl, 'https://dup.example/a.m3u8');
      expect(registry.sources.first.streamSecretRef, isNull);
      expect(registry.sources.first.lastSuccessfulPlaybackAt, isNull);
      expect(registry.sources.first.lastFailedPlaybackAt, isNull);
      expect(registry.members.first.normalizedName, 'dup tv');
      expect(registry.members.first.displayName, 'Dup TV');
      expect(registry.members.first.group, 'News');
      expect(registry.members.first.countryCode, 'IR');
      expect(registry.members.first.ordinal, 0);
      expect(registry.members.last.ordinal, 1);
      // Identity rule 1 keys on the *stripped* provider ID, while the member still records the
      // raw attribute so a later `@SD`-suffixed feed can be recognised as the same station.
      expect(registry.members.first.providerChannelId, 'Dup');
      expect(registry.members.first.tvgId, 'Dup.ir');
      // Persian labels with Persian digits: the first source is named, later ones counted.
      expect(registry.sources.first.label, 'منبع اصلی');
      expect(registry.sources.map((s) => s.label).toList()[1], 'منبع ۲');
      expect(registry.sources.last.label, 'منبع اصلی');
      expect(registry.issues, isEmpty);
    });

    test('protocol hints come from the canonical path extension only', () {
      final parsed = parsePlaylist(
        playlistId: 'playlist:hint',
        text: '#EXTM3U\n'
            '#EXTINF:-1 tvg-id="Hints.ir",Hints TV\n'
            'https://cdn.example/a.m3u8\n'
            'https://cdn.example/b.mpd\n'
            'https://cdn.example/c.MP4?x=M3U8\n'
            'https://cdn.example/d.m3u8?sig=1\n'
            'https://cdn.example/stream\n',
      );
      final registry = registerParsedPlaylist(
        parsed: parsed,
        playlistId: 'playlist:hint',
        providerNamespace: 'fixture:provider',
      );
      expect(
        registry.sources.map((s) => s.protocolHint).toList(),
        ['hls', 'dash', 'mp4', 'hls', 'unknown'],
      );
    });

    test('canonical URLs drop default ports and fragments, never path case', () {
      expect(canonicalStreamUrl('HTTPS://CDN.Example:443/Live.A.m3u8?Q=1'),
          'https://cdn.example/Live.A.m3u8?Q=1');
      expect(canonicalStreamUrl('http://cdn.example:80/a.m3u8'),
          'http://cdn.example/a.m3u8');
      expect(canonicalStreamUrl('https://cdn.example/a.m3u8#top'), isNull);
      expect(canonicalStreamUrl('ftp://cdn.example/a.m3u8'), isNull);
      expect(canonicalStreamUrl('not a url'), isNull);
      expect(canonicalStreamUrl('https://cdn.example'), isNull,
          reason: 'no path means no manifest to play, so it is not a usable stream');
      expect(canonicalStreamUrl('https://user:pass@cdn.example/a.m3u8'), isNull,
          reason: 'userinfo is a credential, not part of a canonical address');
    });

    test('sensitive URLs are detected by userinfo and by query key', () {
      expect(isSensitiveUrl('https://user:pass@cdn.example/a.m3u8'), isTrue);
      expect(isSensitiveUrl('https://cdn.example/a.m3u8?token=abc'), isTrue);
      expect(isSensitiveUrl('https://cdn.example/a.m3u8?Key=abc'), isTrue);
      // A query is only a query after a `?`, so this row spells the parameter list the way a CDN
      // actually writes one; a bare `;` would still be part of the path and must not be treated
      // as a credential.
      expect(isSensitiveUrl('https://cdn.example/a.m3u8?x=1&Signature=abc'), isTrue);
      expect(isSensitiveUrl('https://cdn.example/a.m3u8;Signature=abc'), isFalse);
      expect(isSensitiveUrl('https://cdn.example/a.m3u8?auth=1'), isTrue);
      expect(isSensitiveUrl('https://cdn.example/a.m3u8?credential=x'), isTrue);
      expect(isSensitiveUrl('https://cdn.example/a.m3u8?password=x'), isTrue);
      expect(isSensitiveUrl('https://cdn.example/a.m3u8?quality=720'), isFalse);
      // A word that merely contains a sensitive key must not trip the check, or a legitimate
      // `authorize` path parameter would silently lose its channel.
      expect(isSensitiveUrl('https://cdn.example/monkey.m3u8'), isFalse);
      expect(isSensitiveUrl('https://cdn.example/a.m3u8?monkey=1'), isFalse);
    });

    test('a credential-bearing URL never becomes a plaintext stream URL', () {
      // The registry refuses a sensitive address rather than storing it: `streamUrl` is a
      // runtime-only field and no secret store has been verified on any platform yet.
      final parsed = parsePlaylist(
        playlistId: 'playlist:secret',
        text: '#EXTM3U\n#EXTINF:-1 tvg-id="Secret.ir",Secret TV\n'
            'https://cdn.example/a.m3u8?token=abc\n'
            'https://cdn.example/b.m3u8\n',
      );
      final registry = registerParsedPlaylist(
        parsed: parsed,
        playlistId: 'playlist:secret',
        providerNamespace: 'fixture:provider',
      );
      expect(registry.sources.length, 1);
      expect(registry.sources.single.streamUrl, 'https://cdn.example/b.m3u8');
      expect(registry.sources.single.priority, 0);
      // `secretStorageUnavailable` is the honest code: the address parsed fine, and it is
      // refused because no platform has a verified secret store to put it in — not because
      // it is malformed. Storing it as plaintext `streamUrl` would break the rule that a
      // credential-bearing address is never persisted, so it is dropped with this issue.
      expect(registry.issues.map((i) => i.code), contains('secretStorageUnavailable'));
    });

    test('duplicate canonical addresses inside one member collapse', () {
      final parsed = parsePlaylist(
        playlistId: 'playlist:case',
        text: '#EXTM3U\n#EXTINF:-1 tvg-id="Same.ir",Same TV\n'
            'https://cdn.example/a.m3u8\n'
            'HTTPS://CDN.Example/a.m3u8\n',
      );
      final registry = registerParsedPlaylist(
        parsed: parsed,
        playlistId: 'playlist:case',
        providerNamespace: 'fixture:provider',
      );
      expect(registry.members.length, 1);
      expect(registry.sources.length, 1);
      // Deduplicating a canonical match is not an error and not a ceiling: `limitExceeded`
      // belongs to the 200,000-line / 50,000-member / 100-URL ceilings only, so a silent
      // collapse here must produce no issue. Asserting emptiness is what stops a future
      // implementation from reporting every dedupe as a failure to the user.
      expect(registry.issues, isEmpty);
      expect(registry.sources.single.streamUrl, 'https://cdn.example/a.m3u8');
      // Canonicalization must be idempotent, or a refresh that re-canonicalizes an already
      // stored address would mint a new sourceId every time and lose its history.
      expect(canonicalStreamUrl(registry.sources.single.streamUrl),
          registry.sources.single.streamUrl);
      expect(registry.sources.single.sourceId,
          'source:${stableKeyHash('${registry.members.single.memberId}\nurl\nhttps://cdn.example/a.m3u8')}');
    });

    test('an over-long URL is dropped instead of truncated into a wrong address', () {
      final parsed = parsePlaylist(
        playlistId: 'playlist:urltoolong',
        text: '#EXTM3U\n#EXTINF:-1 tvg-id="Long.ir",Long TV\n'
            'https://cdn.example/${'a' * 8193}.m3u8\n'
            'https://cdn.example/ok.m3u8\n',
      );
      final registry = registerParsedPlaylist(
        parsed: parsed,
        playlistId: 'playlist:urltoolong',
        providerNamespace: 'fixture:provider',
      );
      expect(registry.sources.length, 1);
      expect(registry.sources.single.streamUrl, 'https://cdn.example/ok.m3u8');
      expect(parsed.truncated, isTrue);
      expect(parsed.issues.map((i) => i.code), contains('limitExceeded'));
    });

    test('the registry is a pure function of the same parse result', () {
      final parsed = parsePlaylist(
        playlistId: 'playlist:duplicates',
        text: _fixture('duplicates.m3u'),
      );
      final first = registerParsedPlaylist(
        parsed: parsed,
        playlistId: 'playlist:duplicates',
        providerNamespace: 'fixture:provider',
      );
      final second = registerParsedPlaylist(
        parsed: parsed,
        playlistId: 'playlist:duplicates',
        providerNamespace: 'fixture:provider',
      );
      expect(
        second.sources.map((s) => s.sourceId).toList(),
        first.sources.map((s) => s.sourceId).toList(),
      );
      expect(
        second.members.map((m) => m.memberId).toList(),
        first.members.map((m) => m.memberId).toList(),
      );
      // A different namespace must produce different member IDs, or two providers would
      // silently merge their identically-named channels.
      final other = registerParsedPlaylist(
        parsed: parsed,
        playlistId: 'playlist:duplicates',
        providerNamespace: 'fixture:other',
      );
      expect(other.members.first.memberId, isNot(first.members.first.memberId));
    });
  });

  group('contract shapes', () {
    test('no registered source carries a secret reference or a capability claim', () {
      final registry = registerParsedPlaylist(
        parsed: parsePlaylist(
          playlistId: 'playlist:valid',
          text: _fixture('valid.m3u'),
        ),
        playlistId: 'playlist:valid',
        providerNamespace: 'builtin:ccloud',
      );
      expect(registry.sources, isNotEmpty);
      expect(
        registry.sources.every((s) => s.streamSecretRef == null),
        isTrue,
        reason: 'no verified secret store exists on any platform yet',
      );
      expect(
        registry.sources.every((s) => rendererSupportValues.contains(s.rendererCapability)),
        isTrue,
      );
      expect(
        registry.sources.every((s) => s.health != SourceHealth.available),
        isTrue,
        reason: 'parsing a playlist is not evidence that a stream plays',
      );
      expect(
        registry.members.every((m) => m.providerNamespace == 'builtin:ccloud'),
        isTrue,
      );
    });

    test('a playlist with no usable row registers nothing', () {
      final registry = registerParsedPlaylist(
        parsed: parsePlaylist(
          playlistId: 'playlist:empty',
          text: _fixture('empty.m3u'),
        ),
        playlistId: 'playlist:empty',
        providerNamespace: 'fixture:provider',
      );
      expect(registry.members, isEmpty);
      expect(registry.sources, isEmpty);
      expect(registry.issues, isEmpty);
    });
  });
}
