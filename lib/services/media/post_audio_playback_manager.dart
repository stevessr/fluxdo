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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!backgroundAllowed &&
        (state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden ||
            state == AppLifecycleState.inactive)) {
      unawaited(player.pause());
    }
  }

  Future<void> toggle(String url) async {
    if (activeUrl == url) {
      if (player.playing) {
        await player.pause();
      } else {
        unawaited(player.play());
      }
      notifyListeners();
      return;
    }

    // Stop previous audio before switching the shared player.
    await player.stop();
    activeUrl = url;
    notifyListeners();
    try {
      await player.setAudioSource(AudioSource.uri(
        Uri.parse(url),
        tag: MediaItem(
          id: url,
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
