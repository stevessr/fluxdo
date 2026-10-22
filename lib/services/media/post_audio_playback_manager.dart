import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

/// One long-lived audio session; inline post widgets may be recycled while
/// a morning-news recording continues in the background.
class PostAudioPlaybackManager extends ChangeNotifier with WidgetsBindingObserver {
  PostAudioPlaybackManager._() {
    WidgetsBinding.instance.addObserver(this);
  }
  static final instance = PostAudioPlaybackManager._();

  final AudioPlayer player = AudioPlayer();
  String? activeUrl;
  bool backgroundAllowed = true;

  // Serialize source changes so a second tap cannot race an unfinished load.
  Future<void> _pending = Future<void>.value();

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!backgroundAllowed &&
        (state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden)) {
      unawaited(player.pause());
    }
  }

  Future<void> toggle(String url) {
    final request = _pending.then((_) => _toggleNow(url));
    // An unsuccessful source must not poison all subsequent playback actions.
    _pending = request.catchError((Object error, StackTrace stack) {
      debugPrint('[Audio] Playback transition failed: $error');
    });
    return request;
  }

  Future<void> setSpeed(double speed) async {
    await player.setSpeed(speed);
    notifyListeners();
  }

  Future<void> _toggleNow(String url) async {
    if (activeUrl == url) {
      if (player.playing) {
        await player.pause();
      } else {
        if (player.processingState == ProcessingState.completed) {
          await player.seek(Duration.zero);
        }
        unawaited(player.play());
      }
      notifyListeners();
      return;
    }

    await player.stop();
    activeUrl = url;
    notifyListeners();
    try {
      await player.setAudioSource(AudioSource.uri(
        Uri.parse(url),
        tag: MediaItem(
          id: url.hashCode.toUnsigned(32).toRadixString(16),
          title: 'LINUX DO 音频',
          album: 'LINUX DO',
        ),
      ));
      unawaited(player.play());
    } catch (_) {
      activeUrl = null;
      notifyListeners();
      rethrow;
    }
  }

}
