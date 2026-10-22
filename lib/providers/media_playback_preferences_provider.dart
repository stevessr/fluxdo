import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'preferences_provider.dart';
import '../services/media/post_audio_playback_manager.dart';

/// Local-only media playback preferences, independent of site account settings.
class MediaPlaybackPreferences {
  const MediaPlaybackPreferences({
    this.backgroundAudio = true,
    this.pictureInPicture = true,
  });

  final bool backgroundAudio;
  final bool pictureInPicture;
}

class MediaPlaybackPreferencesNotifier extends StateNotifier<MediaPlaybackPreferences> {
  MediaPlaybackPreferencesNotifier(this._prefs)
      : super(MediaPlaybackPreferences(
          backgroundAudio: _prefs.getBool(backgroundAudioKey) ?? true,
          pictureInPicture: _prefs.getBool(pictureInPictureKey) ?? true,
        ));

  static const backgroundAudioKey = 'pref_media_background_audio';
  static const pictureInPictureKey = 'pref_media_picture_in_picture';

  final SharedPreferences _prefs;

  Future<void> setBackgroundAudio(bool value) async {
    PostAudioPlaybackManager.instance.backgroundAllowed = value;
    if (!value) { await PostAudioPlaybackManager.instance.player.pause(); }
    state = MediaPlaybackPreferences(
      backgroundAudio: value,
      pictureInPicture: state.pictureInPicture,
    );
    await _prefs.setBool(backgroundAudioKey, value);
  }

  Future<void> setPictureInPicture(bool value) async {
    state = MediaPlaybackPreferences(
      backgroundAudio: state.backgroundAudio,
      pictureInPicture: value,
    );
    await _prefs.setBool(pictureInPictureKey, value);
  }
}

final mediaPlaybackPreferencesProvider = StateNotifierProvider<
    MediaPlaybackPreferencesNotifier, MediaPlaybackPreferences>((ref) {
  return MediaPlaybackPreferencesNotifier(ref.read(sharedPreferencesProvider));
});
