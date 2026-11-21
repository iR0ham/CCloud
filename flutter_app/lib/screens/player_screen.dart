import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:window_manager/window_manager.dart' show WindowManager;

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
  Timer? _progressTimer;
  Timer? _toastTimer;

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
  Duration _buffered = Duration.zero;
  bool _playing = false;
  bool _buffering = true;
  bool _completed = false;
  bool _showControls = true;
  String? _error;
  bool _isLive = false;
  int _countdown = 0;

  double _volume = 0.85;
  double _lastAudibleVolume = 0.85;
  double _speed = 1.0;
  List<AudioTrack> _audioTracks = const [];
  String? _selectedAudioId;
  String? _toast;
  /// Mobile opens the player in immersive mode, so it starts "full screen";
  /// desktop windows keep their frame until F / the button asks otherwise.
  bool _fullscreen = Platform.isAndroid || Platform.isIOS;
  bool _scrubbing = false;
  double _scrubFraction = 0;
  bool _historyStarted = false;
  bool _successRecorded = false;

  /// Where the original play request asked to start; kept for retries the way
  /// the macOS controller keeps `request.startAt`.
  double _requestStart = 0;
  int _openGeneration = 0;
  late final bool _vlcAvailable = _detectVlc();

  @override
  void initState() {
    super.initState();
    _args = widget.args;
    _requestStart = widget.startAt;
    WidgetsBinding.instance.addObserver(this);
    _player = Player();
    _controller = VideoController(
      _player,
      configuration: const VideoControllerConfiguration(
        enableHardwareAcceleration: true,
      ),
    );
    unawaited(_player.setVolume(_volume * 100));
    _attachStreams();
    if (_fullscreen) _enterFullscreen();
    _setWakelock(true);
    unawaited(_boot());
    _healthTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _checkHealth(),
    );
    _progressTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _tickProgress(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _rootFocus.requestFocus();
    });
  }

  void _setWakelock(bool enabled) {
    final action = enabled ? WakelockPlus.enable() : WakelockPlus.disable();
    unawaited(action.catchError((_) {}));
  }

  bool _detectVlc() {
    if (!Platform.isWindows) return true;
    return const [
      r'C:\Program Files\VideoLAN\VLC\vlc.exe',
      r'C:\Program Files (x86)\VideoLAN\VLC\vlc.exe',
    ].any((path) => File(path).existsSync());
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
          _markStarted();
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
      _player.stream.buffer.listen((value) {
        if (!mounted) return;
        setState(() => _buffered = value);
      }),
    );
    _subscriptions.add(
      _player.stream.playing.listen((value) {
        if (!mounted) return;
        setState(() => _playing = value);
        if (value) {
          _markStarted();
          _recordLinkSuccess();
          unawaited(_player.setRate(_speed).catchError((_) {}));
        }
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
      _player.stream.tracks.listen((tracks) {
        if (!mounted) return;
        _applyTracks(tracks);
      }),
    );
    _subscriptions.add(
      _player.stream.track.listen((track) {
        if (!mounted) return;
        final id = track.audio.id;
        if (id.isEmpty || id == _selectedAudioId) return;
        setState(() => _selectedAudioId = id);
      }),
    );
    _subscriptions.add(
      _player.stream.error.listen((value) {
        if (!mounted) return;
        _lastError = value;
        // mpv also reports recoverable errors (a dropped segment, for example)
        // while playback continues; only restart when the picture really stopped.
        final stalled =
            !_playing ||
            DateTime.now().difference(_lastProgressAt).inSeconds >= 6;
        if (stalled) unawaited(_recover());
      }),
    );
  }

  void _applyTracks(Tracks tracks) {
    final audio = tracks.audio
        .where((track) => track.id != 'auto' && track.id != 'no')
        .toList();
    setState(() {
      _audioTracks = audio;
      if (audio.length <= 1) {
        _selectedAudioId = audio.isEmpty ? null : audio.first.id;
      } else if (!audio.any((track) => track.id == _selectedAudioId)) {
        _selectedAudioId = audio.first.id;
      }
    });
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
  }

  void _buildRotation(String preference) {
    final preferred = _pickSourceFor(_args, preference);
    final playable = _args.sources
        .where((s) => s.url.isNotEmpty && !s.isTrailer)
        .toList();
    if (preferred != null) {
      playable.removeWhere((s) => s.id == preferred.id);
      playable.insert(0, preferred);
    }
    // Preferred quality first, then the API order, then links that already
    // burned twice in earlier sessions.
    final health = AppServices.instance.linkHealth;
    final fresh = playable
        .where((s) => !health.isDeprioritised(s.url))
        .toList();
    final burned = playable
        .where((s) => health.isDeprioritised(s.url))
        .toList();
    _rotation
      ..clear()
      ..addAll([...fresh, ...burned]);
    _rotationIndex = 0;
    _reloadTries = 0;
  }

  MediaSource? _nextSource() {
    if (_rotationIndex + 1 >= _rotation.length) return null;
    _rotationIndex += 1;
    return _rotation[_rotationIndex];
  }

  /// Live TV keeps the stream alive the way the macOS app does: retry the same
  /// link twice, fall back to software decoding, then move on to the next source.
  Future<void> _recover() async {
    if (!mounted || _recovering) return;
    if (_recoveriesLeft <= 0) {
      await _rememberFailure();
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
        setState(() => _note = 'در حال ازسرگیری پخش…');
        await _open(current, keepNote: true);
        return;
      }
      await _rememberFailure();
      final next = _nextSource();
      if (next != null) {
        _reloadTries = 0;
        if (!mounted) return;
        setState(
          () => _note = _rotation.length > 1
              ? 'منبع ${faDigits(_rotationIndex + 1)} از ${faDigits(_rotation.length)} در حال امتحان…'
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

  Future<void> _rememberFailure() async {
    final current = _source;
    if (current == null) return;
    await AppServices.instance.linkHealth.recordFailure(current.url);
  }

  void _recordLinkSuccess() {
    final current = _source;
    if (current == null || _successRecorded) return;
    _successRecorded = true;
    unawaited(AppServices.instance.linkHealth.recordSuccess(current.url));
  }

  void _showFinalError() {
    if (!mounted) return;
    final message = _lastError?.trim() ?? '';
    setState(() {
      _note = null;
      _buffering = false;
      if (_isLive) {
        _error = message.isEmpty
            ? 'این شبکه پخش نشد؛ ممکن است لینک آن خراب یا در دسترس نباشد.'
            : 'این شبکه پخش نشد.\n$message';
      } else {
        _error = message.isEmpty ? 'خطای نامشخص در پخش این سورس' : message;
      }
    });
  }

  void _checkHealth() {
    if (!mounted) return;
    if (_source == null || _error != null || _recovering) return;
    final stalled = DateTime.now().difference(_lastProgressAt).inSeconds;
    if (!_isLive) {
      // A VOD that had started and then sits buffering is stuck, not loading.
      if (_everPlayed && _playing && _buffering && stalled >= 15) {
        unawaited(_recover());
      }
      return;
    }
    if (!_playing && _everPlayed) {
      _lastProgressAt = DateTime.now();
      return;
    }
    final limit = _everPlayed ? 12 : 22;
    if (stalled >= limit) {
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
    _historyStarted = false;
    _successRecorded = false;
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
    _successRecorded = false;
    _historyStarted = false;
    final start = resumeAt != null
        ? resumeAt.inMilliseconds / 1000
        : _resumeOffset;
    final generation = ++_openGeneration;
    setState(() {
      _source = source;
      _error = null;
      _buffering = true;
      _completed = false;
      _buffered = Duration.zero;
      _scrubbing = false;
      _everPlayed = false;
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
    unawaited(_player.setVolume(_volume * 100).catchError((_) {}));
    if (!mounted || generation != _openGeneration) return;
    _applyTracks(_player.state.tracks);
    if (start > 0.5) {
      unawaited(_seekAfterOpen(start, generation));
    }
  }

  /// Resumes at [seconds] once the duration is known, clamped like the macOS
  /// player (`duration - 0.5` for a resume, unlike the `duration - 0.05` seek
  /// ceiling used by timeline drags and key presses).
  Future<void> _seekAfterOpen(double seconds, int generation) async {
    for (var i = 0; i < 40; i++) {
      if (_duration > const Duration(seconds: 1)) break;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted || generation != _openGeneration) return;
    }
    if (_duration <= Duration.zero) return;
    final target = Duration(milliseconds: (seconds * 1000).round());
    final ceiling = _duration > const Duration(seconds: 1)
        ? _duration - const Duration(milliseconds: 500)
        : target;
    final clamped = target > ceiling ? ceiling : target;
    await _player.seek(clamped < Duration.zero ? Duration.zero : clamped);
  }

  Duration _clampedSeek(Duration target) {
    final floor = Duration.zero;
    if (_duration <= const Duration(milliseconds: 100)) {
      return target < floor ? floor : target;
    }
    final ceiling = _duration - const Duration(milliseconds: 50);
    if (target < floor) return floor;
    return target > ceiling ? ceiling : target;
  }

  /// Start offset for an automatic (re)load, mirroring the macOS `resumeOffset`:
  /// a title that had started picks up five seconds back; anything else starts
  /// at the offset the original request asked for.
  double get _resumeOffset {
    if (_everPlayed && _duration > const Duration(seconds: 1)) {
      final seconds = _position.inMilliseconds / 1000 - 5;
      return seconds < 0 ? 0 : seconds;
    }
    return _requestStart;
  }

  void _markStarted() {
    if (_historyStarted) return;
    _historyStarted = true;
    _recordProgress();
    _recordLinkSuccess();
  }

  void _tickProgress() {
    if (!mounted || !_historyStarted || !_playing) return;
    if (_duration <= const Duration(seconds: 1)) return;
    _recordProgress();
  }

  void _recordProgress({bool atEnd = false}) {
    final media = _args.media;
    if (media == null) return;
    final duration = _duration;
    if (duration <= const Duration(seconds: 1)) return;
    final position = atEnd ? duration : _position;
    final total = duration.inMilliseconds;
    final progress = total > 0
        ? (position.inMilliseconds / total).clamp(0.0, 1.0)
        : 0.0;
    AppServices.instance.history.record(
      media,
      progress: progress,
      position: position.inMilliseconds / 1000,
      duration: duration.inMilliseconds / 1000,
      episodeId: _args.episodeId,
      seasonTitle: _args.seasonTitle,
      episodeLabel: _args.episodeLabel,
    );
  }

  void _onCompleted() {
    _recordProgress(atEnd: true);
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
      // A new episode is a new request: it always starts at zero.
      _everPlayed = false;
      _requestStart = 0;
    });
    _buildRotation(AppServices.instance.settings.preferredQuality);
    _recoveriesLeft = 6;
    _lastError = null;
    return source;
  }

  /// SystemChrome is implemented by the Android/iOS embedders only. Desktop
  /// shells (Windows/macOS/Linux) toggle the real window through
  /// window_manager, which is what the macOS app does with its NSWindow.
  bool get _mobilePlatform => Platform.isAndroid || Platform.isIOS;

  void _enterFullscreen() {
    if (!_mobilePlatform) {
      _setWindowFullscreen(true);
      return;
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (Platform.isAndroid && !PlatformInfo.isTv) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  void _exitFullscreen() {
    if (!_mobilePlatform) {
      _setWindowFullscreen(false);
      return;
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  /// Windowed fullscreen for the desktop shells; a backend that cannot do it
  /// keeps the in-app full-window route.
  void _setWindowFullscreen(bool value) {
    if (!(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) return;
    try {
      final window = WindowManager.instance.getCurrent();
      if (window != null) window.isFullScreen = value;
    } catch (_) {}
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
    var starting = false;
    if (_completed) {
      _player.seek(Duration.zero);
      _player.play();
      setState(() => _completed = false);
      starting = true;
    } else if (_player.state.playing) {
      _player.pause();
    } else {
      _player.play();
      starting = true;
    }
    if (starting) unawaited(_player.setRate(_speed).catchError((_) {}));
    _resetHideTimer();
  }

  void _seekRelative(int seconds) {
    if (_timelineLive) return;
    final target = _position + Duration(seconds: seconds);
    _player.seek(_clampedSeek(target));
    _resetHideTimer();
  }

  bool get _timelineLive => _isLive || _duration <= const Duration(seconds: 1);

  void _toggleFullscreen() {
    setState(() => _fullscreen = !_fullscreen);
    if (_fullscreen) {
      _enterFullscreen();
    } else {
      _exitFullscreen();
    }
    _resetHideTimer();
  }

  void _handleEscape() {
    if (_fullscreen) {
      _toggleFullscreen();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _setVolume(double value) {
    final clamped = value.clamp(0.0, 1.0);
    if ((clamped - _volume).abs() < 0.0001) return;
    setState(() => _volume = clamped);
    unawaited(_player.setVolume(clamped * 100).catchError((_) {}));
  }

  void _changeVolume(double delta) {
    _setVolume(_volume + delta);
    _showToast('صدا: ٪${faDigits((_volume * 100).round())}');
    _resetHideTimer();
  }

  void _toggleMute() {
    if (_volume > 0.01) {
      _lastAudibleVolume = _volume;
      _setVolume(0);
    } else {
      _setVolume(_lastAudibleVolume < 0.05 ? 0.05 : _lastAudibleVolume);
    }
    _showToast(_volume > 0.01 ? 'صدا روشن شد' : 'صدا قطع شد');
    _resetHideTimer();
  }

  void _setSpeed(double value) {
    final clamped = value.clamp(0.5, 2.0);
    setState(() => _speed = clamped);
    if (_playing) unawaited(_player.setRate(clamped).catchError((_) {}));
    _resetHideTimer();
  }

  String _audioLabel(AudioTrack track, int ordinal) => audioTrackLabel(
    title: track.title,
    language: track.language,
    ordinal: ordinal,
  );

  String get _selectedAudioLabel {
    final index = _audioTracks.indexWhere((t) => t.id == _selectedAudioId);
    if (index < 0) return 'صدا';
    return _audioLabel(_audioTracks[index], index);
  }

  void _showToast(String message) {
    _toastTimer?.cancel();
    setState(() => _toast = message);
    _toastTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _toast = null);
    });
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      _togglePlay();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _seekRelative(-10);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _seekRelative(10);
    } else if (key == LogicalKeyboardKey.escape) {
      _handleEscape();
    } else if (key == LogicalKeyboardKey.keyF) {
      _toggleFullscreen();
    } else if (key == LogicalKeyboardKey.keyM) {
      _toggleMute();
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _changeVolume(0.05);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _changeVolume(-0.05);
    } else if (key == LogicalKeyboardKey.keyN) {
      if (_args.upcoming.isNotEmpty) _playNextNow();
    } else if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.mediaPlayPause) {
      _onSelectKey();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Future<void> _copySourceLink() async {
    final url = _source?.url;
    if (url == null) return;
    await Clipboard.setData(ClipboardData(text: url));
    _showToast('لینک سورس کپی شد');
  }

  Future<void> _openInVlc() async {
    final url = _source?.url;
    if (url == null) return;
    var launchedDirectly = false;
    if (Platform.isWindows) {
      for (final path in const [
        r'C:\Program Files\VideoLAN\VLC\vlc.exe',
        r'C:\Program Files (x86)\VideoLAN\VLC\vlc.exe',
      ]) {
        if (!File(path).existsSync()) continue;
        try {
          await Process.start(path, [url], mode: ProcessStartMode.detached);
          launchedDirectly = true;
        } catch (_) {}
        break;
      }
    } else if (Platform.isMacOS) {
      try {
        await Process.start('open', [
          '-a',
          'VLC',
          url,
        ], mode: ProcessStartMode.detached);
        launchedDirectly = true;
      } catch (_) {}
    }
    if (launchedDirectly) return;
    final uri = Uri.tryParse(url);
    var opened = false;
    if (uri != null) {
      try {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
    if (!opened) {
      await _copySourceLink();
      return;
    }
    if (Platform.isWindows && !_vlcAvailable) {
      _showToast('VLC نصب نیست؛ لینک در برنامه پیشفرض باز شد');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _player.pause();
      if (_historyStarted) _recordProgress();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _countdownTimer?.cancel();
    _healthTimer?.cancel();
    _progressTimer?.cancel();
    _toastTimer?.cancel();
    if (_historyStarted) _recordProgress();
    _rootFocus.dispose();
    _backFocus.dispose();
    _nextFocus.dispose();
    WidgetsBinding.instance.removeObserver(this);
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _player.dispose();
    _setWakelock(false);
    _exitFullscreen();
    super.dispose();
  }

  String _format(Duration value) =>
      formatPlayerTime(value.inMilliseconds / 1000);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _rootFocus,
        autofocus: true,
        onKeyEvent: _handleKeyEvent,
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
            if (_toast != null) _toastLayer(_toast!),
            if (_countdown > 0) _autoNextOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _autoNextOverlay() {
    final upcoming = _args.upcoming;
    final next = upcoming.isNotEmpty ? upcoming.first : null;
    final nextTitle = next?.subtitle ?? next?.episodeLabel ?? next?.title;
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

  Widget _toastLayer(String message) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 96),
          child: IgnorePointer(
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle_rounded,
                      color: AppColors.green,
                      size: 15,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      message,
                      style: const TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
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
      color: Colors.black.withValues(alpha: 0.55),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Container(
              padding: const EdgeInsets.all(26),
              constraints: const BoxConstraints(maxWidth: 560),
              decoration: BoxDecoration(
                color: const Color(0xFF14161F),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: AppColors.red,
                    size: 34,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'پخش ناموفق بود',
                    style: TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 11.5,
                      height: 1.7,
                      color: Colors.white.withValues(alpha: 0.72),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: _retryAll,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          minimumSize: const Size(0, 40),
                        ),
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('تلاش دوباره'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _openInVlc,
                        style: _overlayButtonStyle,
                        icon: const Icon(
                          Icons.play_circle_outline_rounded,
                          size: 17,
                        ),
                        label: const Text('باز کردن در VLC'),
                      ),
                      OutlinedButton(
                        onPressed: _copySourceLink,
                        style: _overlayButtonStyle,
                        child: const Text('کپی لینک'),
                      ),
                      OutlinedButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        style: _overlayButtonStyle,
                        child: const Text('بستن'),
                      ),
                    ],
                  ),
                  if (Platform.isWindows && !_vlcAvailable) ...[
                    const SizedBox(height: 12),
                    Text(
                      'VLC روی این ویندوز نصب نیست؛ در این حالت لینک با برنامهٔ پیش‌فرض باز می‌شود.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: AppTheme.fontFamily,
                        fontSize: 9.5,
                        color: Colors.white.withValues(alpha: 0.40),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  ButtonStyle get _overlayButtonStyle => OutlinedButton.styleFrom(
    foregroundColor: Colors.white,
    side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
    minimumSize: const Size(0, 40),
    textStyle: const TextStyle(
      fontFamily: AppTheme.fontFamily,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    ),
  );

  Widget _controlsLayer() {
    final wide = MediaQuery.sizeOf(context).width >= 700;
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
                    tooltip: 'بستن پخش‌کننده',
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
                    _menuButton(
                      icon: Icons.tune_rounded,
                      label: _source!.qualityLabel,
                      tooltip: 'انتخاب کیفیت / سورس',
                      wide: wide,
                      onTap: _showSourceSheet,
                    ),
                  if (_audioTracks.length > 1)
                    _menuButton(
                      icon: Icons.graphic_eq_rounded,
                      label: _selectedAudioLabel,
                      tooltip: 'انتخاب صدای ویدئو',
                      wide: wide,
                      onTap: _showAudioSheet,
                    ),
                  _menuButton(
                    icon: Icons.speed_rounded,
                    label: speedLabel(_speed),
                    tooltip: 'سرعت پخش',
                    wide: wide,
                    onTap: _showSpeedSheet,
                  ),
                  _roundButton(
                    icon: _fullscreen
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                    onTap: _toggleFullscreen,
                    tooltip: _fullscreen ? 'خروج از تمام‌صفحه' : 'تمام‌صفحه',
                  ),
                  if (_args.upcoming.isNotEmpty)
                    _roundButton(
                      icon: Icons.skip_next_rounded,
                      onTap: () {
                        final source = _advanceToNext();
                        if (source != null) _open(source);
                      },
                      tooltip: 'پخش قسمت بعد',
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
                  _timelineRow(),
                  const SizedBox(height: 2),
                  _volumeRow(),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (!_timelineLive)
                        _roundButton(
                          icon: Icons.replay_10_rounded,
                          onTap: () => _seekRelative(-10),
                          tooltip: '۱۰ ثانیه عقب',
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
                      if (!_timelineLive)
                        _roundButton(
                          icon: Icons.forward_10_rounded,
                          onTap: () => _seekRelative(10),
                          tooltip: '۱۰ ثانیه جلو',
                        ),
                      if (_args.upcoming.isNotEmpty && !_timelineLive) ...[
                        const SizedBox(width: 18),
                        _roundButton(
                          icon: Icons.skip_next_rounded,
                          onTap: () {
                            final source = _advanceToNext();
                            if (source != null) _open(source);
                          },
                          tooltip: 'قسمت بعد',
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

  double get _displayFraction {
    if (_scrubbing) return _scrubFraction;
    final total = _duration.inMilliseconds;
    if (total <= 0) return 0;
    return (_position.inMilliseconds / total).clamp(0.0, 1.0);
  }

  Duration get _displayPosition {
    if (!_scrubbing) return _position;
    return Duration(
      milliseconds: (_scrubFraction * _duration.inMilliseconds).round(),
    );
  }

  Widget _timelineRow() {
    if (_timelineLive) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.red.withValues(alpha: 0.90),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.circle, color: Colors.white, size: 6),
                  SizedBox(width: 5),
                  Text(
                    'زنده',
                    style: TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 3,
                decoration: BoxDecoration(
                  color: AppColors.red.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text('پخش زنده', style: _timeStyle),
          ],
        ),
      );
    }
    return Row(
      children: [
        Text(_format(_displayPosition), style: _timeStyle),
        const SizedBox(width: 10),
        Expanded(child: _scrubBar()),
        const SizedBox(width: 10),
        Text(_format(_duration), style: _timeStyle),
      ],
    );
  }

  Widget _scrubBar() {
    return SizedBox(
      height: 24,
      child: LayoutBuilder(
        builder: (context, constraints) {
          double fractionFor(Offset position) =>
              (position.dx / constraints.maxWidth).clamp(0.0, 1.0);
          void update(Offset position) {
            if (_duration <= Duration.zero) return;
            setState(() {
              _scrubbing = true;
              _scrubFraction = fractionFor(position);
            });
          }

          void commit() {
            if (!_scrubbing) return;
            final fraction = _scrubFraction;
            setState(() => _scrubbing = false);
            if (_duration > Duration.zero) {
              _player.seek(
                _clampedSeek(
                  Duration(
                    milliseconds: (fraction * _duration.inMilliseconds).round(),
                  ),
                ),
              );
            }
            _resetHideTimer();
          }

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => update(details.localPosition),
            onTapUp: (_) => commit(),
            onHorizontalDragStart: (details) => update(details.localPosition),
            onHorizontalDragUpdate: (details) => update(details.localPosition),
            onHorizontalDragEnd: (_) => commit(),
            child: CustomPaint(
              size: Size(constraints.maxWidth, 24),
              painter: _TimelinePainter(
                fraction: _displayFraction,
                buffered:
                    (_buffered.inMilliseconds /
                            (_duration.inMilliseconds == 0
                                ? 1
                                : _duration.inMilliseconds))
                        .clamp(0.0, 1.0),
                scrubbing: _scrubbing,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _volumeRow() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: Row(
        children: [
          Tooltip(
            message: _volume > 0 ? 'بی‌صدا' : 'باصدا',
            child: AppFocusable(
              onTap: _toggleMute,
              borderRadius: 999,
              focusScale: 1.08,
              child: Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: CustomPaint(
                  size: const Size(20, 20),
                  painter: _VolumeGlyphPainter(volume: _volume),
                ),
              ),
            ),
          ),
          Expanded(
            // A TV remote cannot drag a slider, and letting it take focus would
            // steal the arrow keys from playback; there the mute button and the
            // ↑/↓ keys keep working.
            child: ExcludeFocus(
              excluding: PlatformInfo.isTv,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 5,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
                  activeTrackColor: AppColors.accentBright,
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.26),
                  thumbColor: Colors.white,
                ),
                child: Slider(
                  value: _volume,
                  onChanged: (value) {
                    _setVolume(value);
                    _resetHideTimer();
                  },
                ),
              ),
            ),
          ),
          SizedBox(
            width: 38,
            child: Text(
              '${faDigits((_volume * 100).round())}٪',
              textAlign: TextAlign.end,
              style: const TextStyle(
                fontFamily: AppTheme.fontFamily,
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: Colors.white54,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _timeStyle = TextStyle(
    fontFamily: AppTheme.fontFamily,
    fontSize: 11.5,
    color: Colors.white70,
  );

  Widget _menuButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool wide,
    String? tooltip,
  }) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Tooltip(
        message: tooltip ?? '',
        child: AppFocusable(
          onTap: onTap,
          borderRadius: 999,
          focusScale: 1.06,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: wide ? 10 : 9,
              vertical: 7,
            ),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.50),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 15),
                if (wide) ...[
                  const SizedBox(width: 5),
                  Text(
                    label,
                    style: const TextStyle(
                      fontFamily: AppTheme.fontFamily,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

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

  Future<void> _showAudioSheet() async {
    final tracks = _audioTracks;
    if (tracks.length <= 1) return;
    await showModalBottomSheet<void>(
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
                  'انتخاب صدا',
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              for (var index = 0; index < tracks.length; index++)
                _sheetRow(
                  label: _audioLabel(tracks[index], index),
                  selected: tracks[index].id == _selectedAudioId,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    setState(() => _selectedAudioId = tracks[index].id);
                    unawaited(
                      _player.setAudioTrack(tracks[index]).catchError((_) {}),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showSpeedSheet() async {
    const values = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    await showModalBottomSheet<void>(
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
                  'سرعت پخش',
                  style: TextStyle(
                    fontFamily: AppTheme.fontFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              for (final value in values)
                _sheetRow(
                  label: speedLabel(value),
                  selected: (_speed - value).abs() < 0.001,
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _setSpeed(value);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sheetRow({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return AppFocusable(
      onTap: onTap,
      borderRadius: 12,
      focusScale: 1.01,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accent.withValues(alpha: 0.24)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: selected ? AppColors.accentBright : Colors.white54,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontFamily: AppTheme.fontFamily,
                  fontSize: 13.5,
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

class _TimelinePainter extends CustomPainter {
  const _TimelinePainter({
    required this.fraction,
    required this.buffered,
    required this.scrubbing,
  });

  final double fraction;
  final double buffered;
  final bool scrubbing;

  @override
  void paint(Canvas canvas, Size size) {
    const height = 5.0;
    final top = (size.height - height) / 2;
    final track = Rect.fromLTWH(0, top, size.width, height);
    final radius = Radius.circular(height / 2);

    canvas.drawRRect(
      RRect.fromRectAndRadius(track, radius),
      Paint()..color = Colors.white.withValues(alpha: 0.20),
    );

    final bufferWidth = size.width * buffered.clamp(0.0, 1.0);
    if (bufferWidth > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, top, bufferWidth, height),
          radius,
        ),
        Paint()..color = Colors.white.withValues(alpha: 0.34),
      );
    }

    final playedWidth = size.width * fraction.clamp(0.0, 1.0);
    if (playedWidth > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, top, playedWidth, height),
          radius,
        ),
        Paint()..color = AppColors.accentBright,
      );
    }

    final x = playedWidth.clamp(0.0, size.width);
    canvas.drawCircle(
      Offset(x, size.height / 2),
      scrubbing ? 7 : 5.5,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(_TimelinePainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.buffered != buffered ||
      oldDelegate.scrubbing != scrubbing;
}

/// Speaker glyph with the macOS wave thresholds: slash, one, two or three
/// waves depending on the volume.
class _VolumeGlyphPainter extends CustomPainter {
  const _VolumeGlyphPainter({required this.volume});

  final double volume;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.92)
      ..style = PaintingStyle.fill;
    final speaker = Path()
      ..moveTo(2, size.height * 0.36)
      ..lineTo(size.width * 0.28, size.height * 0.36)
      ..lineTo(size.width * 0.52, size.height * 0.16)
      ..lineTo(size.width * 0.52, size.height * 0.84)
      ..lineTo(size.width * 0.28, size.height * 0.64)
      ..lineTo(2, size.height * 0.64)
      ..close();
    canvas.drawPath(speaker, paint);

    if (volume <= 0.001) {
      final slash = Paint()
        ..color = Colors.white.withValues(alpha: 0.92)
        ..strokeWidth = 1.7
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(
        Offset(size.width * 0.44, size.height * 0.30),
        Offset(size.width * 0.92, size.height * 0.74),
        slash,
      );
      return;
    }

    final waves = volume < 0.35
        ? 1
        : volume < 0.7
        ? 2
        : 3;
    final center = Offset(size.width * 0.50, size.height * 0.5);
    final wavePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.92)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < waves; i++) {
      final radius = size.width * (0.20 + i * 0.14);
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -0.9,
        1.8,
        false,
        wavePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_VolumeGlyphPainter oldDelegate) =>
      oldDelegate.volume != volume;
}
