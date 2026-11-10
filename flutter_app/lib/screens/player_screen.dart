import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/models.dart';
import '../core/playback.dart';
import '../core/platform_info.dart';
import '../core/stores.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.args, this.startAt = 0});

  final PlayerArgs args;
  final double startAt;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  late final Player _player;
  late final VideoController _controller;

  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final FocusNode _rootFocus = FocusNode(debugLabel: 'player-root');
  final FocusNode _backFocus = FocusNode(debugLabel: 'player-back');
  final FocusNode _nextFocus = FocusNode(debugLabel: 'player-next');
  Timer? _hideTimer;
  Timer? _countdownTimer;
  Timer? _healthTimer;

  late PlayerArgs _args;
  late MediaSource? _source;

  /// Playback attempts for the current title, preferred source first.
  final List<MediaSource> _rotation = [];
  int _rotationIndex = 0;
  int _reloadTries = 0;
  int _recoveriesLeft = 6;
  bool _recovering = false;
  bool _everPlayed = false;
  DateTime _lastProgressAt = DateTime.now();
  String? _lastError;
  String? _note;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _buffering = true;
  bool _completed = false;
  bool _showControls = true;
  String? _error;
  bool _isLive = false;
  int _countdown = 0;

  @override
  void initState() {
    super.initState();
    _args = widget.args;
    WidgetsBinding.instance.addObserver(this);
    _player = Player();
    _controller = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );
    _attachStreams();
    _enterFullscreen();
    WakelockPlus.enable();
    unawaited(_boot());
    _healthTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _checkHealth(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _backFocus.requestFocus();
    });
  }

  Future<void> _boot() async {
    await _configureNativePlayer();
    if (!mounted) return;
    await _start();
  }

  /// Network-friendly mpv defaults for IPTV streams: media_kit ships a 5s network
  /// timeout and a disk cache, which abort or stall slow live links.
  Future<void> _configureNativePlayer() async {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    try {
      await Future.wait([
        platform.setProperty('network-timeout', '30'),
        platform.setProperty('cache-on-disk', 'no'),
        platform.setProperty(
          'demuxer-lavf-o',
          'seg_max_retry=20,max_reload=20,reconnect=1,'
              'reconnect_streamed=1,reconnect_delay_max=5,'
              'strict=experimental,allowed_extensions=ALL,'
              'protocol_whitelist=[udp,rtp,tcp,tls,data,file,http,https,crypto]',
        ),
      ]).timeout(const Duration(seconds: 4));
    } catch (_) {
      // Non-native backends keep their defaults.
    }
  }

  void _attachStreams() {
    _subscriptions.add(
      _player.stream.position.listen((value) {
        if (!mounted) return;
        final advanced = value != _position;
        setState(() {
          _position = value;
          if (advanced) _note = null;
        });
        if (advanced) {
          _lastProgressAt = DateTime.now();
          _everPlayed = true;
          _reloadTries = 0;
          _recoveriesLeft = 6;
        }
      }),
    );
    _subscriptions.add(
      _player.stream.duration.listen((value) {
        if (!mounted) return;
        setState(() => _duration = value);
      }),
    );
    _subscriptions.add(
      _player.stream.playing.listen((value) {
        if (!mounted) return;
        setState(() => _playing = value);
        _resetHideTimer();
      }),
    );
    _subscriptions.add(
      _player.stream.buffering.listen((value) {
        if (!mounted) return;
        setState(() => _buffering = value);
      }),
    );
    _subscriptions.add(
      _player.stream.completed.listen((value) {
        if (!mounted) return;
        setState(() {
          _completed = value;
          if (value) _showControls = true;
        });
        if (value) _onCompleted();
      }),
    );
    _subscriptions.add(
      _player.stream.error.listen((value) {
        if (!mounted) return;
        _lastError = value;
        if (!_isLive) {
          setState(() => _error = value);
          return;
        }
        // mpv also reports recoverable errors (a dropped segment, for example)
        // while playback continues; only restart when the picture really stopped.
        final stalled =
            !_playing ||
            DateTime.now().difference(_lastProgressAt).inSeconds >= 6;
        if (stalled) unawaited(_recover());
      }),
    );
  }

  Future<void> _start() async {
    final settings = AppServices.instance.settings;
    _isLive = _args.isLive;
    _buildRotation(settings.preferredQuality);
    final first = _rotation.isEmpty ? null : _rotation.first;
    if (first == null) {
      setState(() => _error = 'منبع قابل پخشی برای این عنوان پیدا نشد');
      return;
    }
    await _open(first);
    _recordStart();
  }

  void _buildRotation(String preference) {
    final preferred = _pickSourceFor(_args, preference);
    final playable = _args.sources
        .where((s) => s.url.isNotEmpty && !s.isTrailer)
        .toList();
    _rotation
      ..clear()
      ..addAll([
        ?preferred,
        ...playable.where((s) => s.id != preferred?.id),
      ]);
    _rotationIndex = 0;
    _reloadTries = 0;
  }

  MediaSource? _nextSource() {
    if (_rotationIndex + 1 >= _rotation.length) return null;
    _rotationIndex += 1;
    return _rotation[_rotationIndex];
  }

  /// Live TV keeps the stream alive the way the macOS app does: retry the same
  /// link, fall back to software decoding, then move on to the next source.
  Future<void> _recover() async {
    if (!mounted || _recovering) return;
    if (_recoveriesLeft <= 0) {
      _showFinalError();
      return;
    }
    _recoveriesLeft -= 1;
    _recovering = true;
    try {
      final current = _source;
      if (current != null && _reloadTries < 2) {
        _reloadTries += 1;
        if (_reloadTries == 2) _applyHwdec('no');
        if (!mounted) return;
        setState(() => _note = 'در حال اتصال دوباره…');
        await _open(current, keepNote: true);
        return;
      }
      final next = _nextSource();
      if (next != null) {
        _reloadTries = 0;
        if (!mounted) return;
        setState(
          () => _note = _rotation.length > 1
              ? 'امتحان منبع ${faDigits(_rotationIndex + 1)} از ${faDigits(_rotation.length)}…'
              : 'در حال اتصال دوباره…',
        );
        await _open(next, keepNote: true);
        return;
      }
      if (!mounted) return;
      _showFinalError();
    } finally {
      _recovering = false;
    }
  }

  void _showFinalError() {
    if (!mounted) return;
    setState(() {
      _note = null;
      _buffering = false;
      _error = _lastError == null || _lastError!.isEmpty
          ? 'این شبکه پخش نشد؛ ممکن است لینک آن خراب یا در دسترس نباشد.'
          : 'این شبکه پخش نشد.\n$_lastError';
    });
  }

  void _checkHealth() {
    if (!mounted || !_isLive) return;
    if (_source == null || _error != null || _recovering) return;
    if (!_playing && _everPlayed) {
      _lastProgressAt = DateTime.now();
      return;
    }
    final limit = _everPlayed ? 12 : 22;
    if (DateTime.now().difference(_lastProgressAt).inSeconds >= limit) {
      unawaited(_recover());
    }
  }

  void _applyHwdec(String value) {
    final platform = _player.platform;
    if (platform is! NativePlayer) return;
    unawaited(platform.setProperty('hwdec', value).catchError((_) {}));
  }

  void _retryAll() {
    _lastError = null;
    _recoveriesLeft = 6;
    _everPlayed = false;
    _lastProgressAt = DateTime.now();
    _buildRotation(AppServices.instance.settings.preferredQuality);
    final first = _rotation.isEmpty ? null : _rotation.first;
    if (first != null) {
      setState(() => _note = null);
      unawaited(_open(first));
    }
  }

  MediaSource? _pickSourceFor(PlayerArgs args, String preference) {
    final playable = args.sources
        .where((s) => s.url.isNotEmpty && !s.isTrailer)
        .toList();
    if (playable.isEmpty) return null;
    if (args.preferredSourceId != null) {
      for (final source in playable) {
        if (source.id == args.preferredSourceId) {
          if (preference == 'auto') return source;
        }
      }
    }
    return preferredSource(playable, preference) ?? playable.first;
  }

  Future<void> _open(
    MediaSource source, {
    Duration? resumeAt,
    bool keepNote = false,
  }) async {
    _cancelCountdown();
    _lastProgressAt = DateTime.now();
    _everPlayed = false;
    setState(() {
      _source = source;
      _error = null;
      _buffering = true;
      _completed = false;
      if (!keepNote) _note = null;
    });
    await _player.open(
      Media(
        source.url,
        httpHeaders: const {
          'User-Agent': 'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36',
        },
      ),
      play: true,
    );
    if (resumeAt != null && resumeAt > Duration.zero) {
      await _player.seek(resumeAt);
    } else if (widget.startAt > 0.02) {
      _seekToFraction(widget.startAt);
    }
  }

  Future<void> _seekToFraction(double fraction) async {
    for (var i = 0; i < 20; i++) {
      if (_duration > const Duration(seconds: 3)) break;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (_duration <= Duration.zero) return;
    final target = Duration(
      milliseconds: (_duration.inMilliseconds * fraction).round(),
    );
    await _player.seek(target);
  }

  void _recordStart() {
    final media = _args.media;
    if (media == null) return;
    AppServices.instance.history.record(
      media,
      progress: 0,
      episodeId: _args.episodeId,
      seasonTitle: _args.seasonTitle,
      episodeLabel: _args.episodeLabel,
    );
  }

  void _recordProgress() {
    final media = _args.media;
    if (media == null) return;
    final total = _duration.inMilliseconds;
    final progress = total > 0
        ? (_position.inMilliseconds / total).clamp(0.0, 1.0)
        : 0.0;
    AppServices.instance.history.record(
      media,
      progress: progress,
      episodeId: _args.episodeId,
      seasonTitle: _args.seasonTitle,
      episodeLabel: _args.episodeLabel,
    );
  }

  void _onCompleted() {
    if (!mounted || _args.upcoming.isEmpty) return;
    if (!AppServices.instance.settings.autoPlayNextEpisode) return;
    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    setState(() => _countdown = 10);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_countdown <= 1) {
        timer.cancel();
        _playNextNow();
        return;
      }
      setState(() => _countdown -= 1);
    });
    if (PlatformInfo.isTv) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _countdown > 0) _nextFocus.requestFocus();
      });
    }
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    if (_countdown != 0) {
      setState(() => _countdown = 0);
      if (_nextFocus.hasFocus) _rootFocus.requestFocus();
    }
  }

  void _playNextNow() {
    _cancelCountdown();
    final source = _advanceToNext();
    if (source != null) {
      _open(source);
    } else {
      _revealControls(focusBack: true);
    }
  }

  /// Switches [_args] to the next queued episode and returns its playable source.
  /// Returns null (leaving the current episode untouched) when nothing is playable.
  MediaSource? _advanceToNext() {
    if (_args.upcoming.isEmpty) return null;
    _cancelCountdown();
    final next = _args.advance();
    final source = _pickSourceFor(
      next,
      AppServices.instance.settings.preferredQuality,
    );
    if (source == null) return null;
    setState(() {
      _args = next;
      _source = source;
    });
    _buildRotation(AppServices.instance.settings.preferredQuality);
    _recoveriesLeft = 6;
    _lastError = null;
    _recordStart();
    return source;
  }

  void _enterFullscreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (Platform.isAndroid && !PlatformInfo.isTv) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  void _exitFullscreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    if (!_playing || _isLive) return;
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() => _showControls = false);
      _rootFocus.requestFocus();
    });
  }

  void _revealControls({bool focusBack = false}) {
    if (!_showControls) setState(() => _showControls = true);
    if (focusBack) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _backFocus.requestFocus();
      });
    }
    _resetHideTimer();
  }

  void _toggleControls() {
    if (_showControls) {
      setState(() => _showControls = false);
      _rootFocus.requestFocus();
    } else {
      _revealControls();
    }
  }

  /// SELECT/Enter with no control focused: reveal controls on TV, otherwise play/pause.
  void _onSelectKey() {
    if (!_showControls) {
      _revealControls(focusBack: true);
    } else {
      _togglePlay();
    }
  }

  void _togglePlay() {
    _cancelCountdown();
    if (_completed) {
      _player.seek(Duration.zero);
      _player.play();
      setState(() => _completed = false);
    } else if (_player.state.playing) {
      _player.pause();
    } else {
      _player.play();
    }
    _resetHideTimer();
  }

  void _seekRelative(int seconds) {
    if (_isLive) return;
    final target = _position + Duration(seconds: seconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : (target > _duration ? _duration : target);
    _player.seek(clamped);
    _resetHideTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _player.pause();
      _recordProgress();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _countdownTimer?.cancel();
    _healthTimer?.cancel();
    _recordProgress();
    _rootFocus.dispose();
    _backFocus.dispose();
    _nextFocus.dispose();
    WidgetsBinding.instance.removeObserver(this);
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _player.dispose();
    WakelockPlus.disable();
    _exitFullscreen();
    super.dispose();
  }

  String _format(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    final seconds = value.inSeconds.remainder(60);
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.arrowRight): _SeekIntent(
            Duration(seconds: 10),
          ),
          SingleActivator(LogicalKeyboardKey.arrowLeft): _SeekIntent(
            Duration(seconds: -10),
          ),
          SingleActivator(LogicalKeyboardKey.select): _PlayPauseIntent(),
          SingleActivator(LogicalKeyboardKey.enter): _PlayPauseIntent(),
          SingleActivator(LogicalKeyboardKey.mediaPlayPause):
              _PlayPauseIntent(),
        },
        child: Actions(
          actions: {
            _SeekIntent: CallbackAction<_SeekIntent>(
              onInvoke: (intent) {
                _seekRelative(intent.offset.inSeconds);
                return null;
              },
            ),
            _PlayPauseIntent: CallbackAction<_PlayPauseIntent>(
              onInvoke: (_) {
                _onSelectKey();
                return null;
              },
            ),
          },
          child: Focus(
            focusNode: _rootFocus,
            autofocus: true,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: Video(
                    controller: _controller,
                    controls: NoVideoControls,
                    fit: BoxFit.contain,
                  ),
                ),
                if (_error != null) _errorLayer(_error!),
                if (_note != null && _error == null)
                  Align(
                    alignment: Alignment.center,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 58),
                      child: IgnorePointer(child: _statusPill(_note!)),
                    ),
                  ),
                if (_buffering && _error == null)
                  const Center(
                    child: SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.6,
                        color: Colors.white,
                      ),
                    ),
                  ),
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _toggleControls,
                  child: AnimatedOpacity(
                    opacity: _showControls ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: ExcludeFocus(
                      excluding: !_showControls,
                      child: IgnorePointer(
                        ignoring: !_showControls,
                        child: _controlsLayer(),
                      ),
                    ),
                  ),
                ),
                if (_countdown > 0) _autoNextOverlay(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _autoNextOverlay() {
    final upcoming = _args.upcoming;
    final next = upcoming.isNotEmpty ? upcoming.first : null;
    final nextTitle = next?.episodeLabel ?? next?.title;
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 122),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF14161F).withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.45),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.skip_next_rounded,
                      color: AppColors.accentBright,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'قسمت بعد در ${faDigits(_countdown)} ثانیه',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: AppTheme.fontFamily,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            nextTitle == null
                                ? 'به‌صورت خودکار پخش می‌شود'
                                : 'بعدی: $nextTitle',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: AppTheme.fontFamily,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.white.withValues(alpha: 0.72),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    AppFocusable(
                      onTap: _playNextNow,
                      focusNode: _nextFocus,
                      borderRadius: 10,
                      focusScale: 1.04,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'پخش حالا',
                          style: TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    AppFocusable(
                      onTap: _cancelCountdown,
                      borderRadius: 10,
                      focusScale: 1.04,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 13,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Text(
                          'لغو',
                          style: TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.white.withValues(alpha: 0.86),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusPill(String message) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF14161F).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white70,
              ),
            ),
            const SizedBox(width: 9),
            Text(
              message,
              textDirection: TextDirection.rtl,
              style: const TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorLayer(String message) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.82),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: AppColors.red,
                size: 40,
              ),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: _retryAll,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('تلاش دوباره'),
                  ),
                  if (_rotation.length > 1)
                    OutlinedButton(
                      onPressed: () {
                        final next = _nextSource();
                        if (next == null) return;
                        _reloadTries = 0;
                        _recoveriesLeft = 6;
                        _open(next);
                      },
                      child: const Text('منبع بعدی'),
                    ),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('بازگشت'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _controlsLayer() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Align(
          alignment: Alignment.topCenter,
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 32),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.75),
                  Colors.transparent,
                ],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  _roundButton(
                    icon: Icons.arrow_forward_rounded,
                    onTap: () => Navigator.of(context).maybePop(),
                    focusNode: _backFocus,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _args.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppTheme.fontFamily,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        if (_args.subtitle != null)
                          Text(
                            _args.subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: AppTheme.fontFamily,
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.72),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (_source != null && _args.sources.length > 1)
                    _roundButton(
                      icon: Icons.tune_rounded,
                      onTap: _showSourceSheet,
                      tooltip: _source!.qualityLabel,
                    ),
                  if (_args.upcoming.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _roundButton(
                        icon: Icons.skip_next_rounded,
                        onTap: () {
                          final source = _advanceToNext();
                          if (source != null) _open(source);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 40, 24, 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.82),
                  Colors.transparent,
                ],
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!_isLive)
                    Row(
                      children: [
                        Text(_format(_position), style: _timeStyle),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 3.5,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6.5,
                              ),
                              overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 14,
                              ),
                              activeTrackColor: AppColors.accentBright,
                              inactiveTrackColor: Colors.white.withValues(
                                alpha: 0.28,
                              ),
                              thumbColor: Colors.white,
                            ),
                            child: Slider(
                              value: _sliderValue,
                              onChanged: (value) {
                                if (_duration <= Duration.zero) return;
                                _player.seek(
                                  Duration(
                                    milliseconds:
                                        (value * _duration.inMilliseconds)
                                            .round(),
                                  ),
                                );
                                _resetHideTimer();
                              },
                            ),
                          ),
                        ),
                        Text(_format(_duration), style: _timeStyle),
                      ],
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.sensors_rounded,
                            color: AppColors.red,
                            size: 16,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'پخش زنده',
                            style: TextStyle(
                              fontFamily: AppTheme.fontFamily,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (!_isLive)
                        _roundButton(
                          icon: Icons.replay_10_rounded,
                          onTap: () => _seekRelative(-10),
                        ),
                      const SizedBox(width: 18),
                      AppFocusable(
                        onTap: _togglePlay,
                        borderRadius: 999,
                        focusScale: 1.08,
                        child: Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _completed && _args.upcoming.isEmpty
                                ? Icons.replay_rounded
                                : (_playing
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded),
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                      const SizedBox(width: 18),
                      if (!_isLive)
                        _roundButton(
                          icon: Icons.forward_10_rounded,
                          onTap: () => _seekRelative(10),
                        ),
                      if (_args.upcoming.isNotEmpty && !_isLive) ...[
                        const SizedBox(width: 18),
                        _roundButton(
                          icon: Icons.skip_next_rounded,
                          onTap: () {
                            final source = _advanceToNext();
                            if (source != null) _open(source);
                          },
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  double get _sliderValue {
    final total = _duration.inMilliseconds;
    if (total <= 0) return 0;
    return (_position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  static const _timeStyle = TextStyle(
    fontFamily: AppTheme.fontFamily,
    fontSize: 11.5,
    color: Colors.white70,
  );

  Widget _roundButton({
    required IconData icon,
    required VoidCallback onTap,
    String? tooltip,
    FocusNode? focusNode,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: AppFocusable(
        onTap: onTap,
        focusNode: focusNode,
        borderRadius: 999,
        focusScale: 1.08,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  void _showSourceSheet() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF15161C),
      builder: (sheetContext) => SafeArea(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 10, right: 6),
                child: Text(
                  'انتخاب منبع',
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              for (final source in _args.sources)
                if (source.url.isNotEmpty && !source.isTrailer)
                  AppFocusable(
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      if (source.id == _source?.id) return;
                      final resume = _position;
                      final index = _rotation.indexWhere(
                        (s) => s.id == source.id,
                      );
                      if (index > 0) {
                        _rotation.insert(0, _rotation.removeAt(index));
                      }
                      _rotationIndex = 0;
                      _reloadTries = 0;
                      _recoveriesLeft = 6;
                      _lastError = null;
                      _open(source, resumeAt: resume);
                      _recordStart();
                    },
                    borderRadius: 12,
                    focusScale: 1.01,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: source.id == _source?.id
                            ? AppColors.accent.withValues(alpha: 0.24)
                            : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            source.id == _source?.id
                                ? Icons.check_circle_rounded
                                : Icons.play_circle_outline_rounded,
                            color: source.id == _source?.id
                                ? AppColors.accentBright
                                : Colors.white70,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              source.qualityLabel,
                              style: const TextStyle(
                                fontFamily: AppTheme.fontFamily,
                                fontSize: 13.5,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          Text(
                            source.kindLabel,
                            style: const TextStyle(
                              fontFamily: AppTheme.fontFamily,
                              fontSize: 11,
                              color: Colors.white54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeekIntent extends Intent {
  const _SeekIntent(this.offset);

  final Duration offset;
}

class _PlayPauseIntent extends Intent {
  const _PlayPauseIntent();
}
