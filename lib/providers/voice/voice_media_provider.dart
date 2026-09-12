import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/voice/mesh_voice_transport.dart';
import '../../services/voice/voice_media_transport.dart';
import '../discourse_providers.dart';
import 'voice_session_provider.dart';

enum VoiceMediaPhase { idle, connecting, connected, unsupported, error }

class VoiceMediaState {
  const VoiceMediaState({
    this.phase = VoiceMediaPhase.idle,
    this.roomId,
    this.transport,
    this.muted = false,
    this.error,
  });

  final VoiceMediaPhase phase;
  final int? roomId;
  final String? transport;
  final bool muted;
  final Object? error;

  bool get connected => phase == VoiceMediaPhase.connected;
}

/// Binds the control-plane Voice session to its concrete media transport.
///
/// The controller is deliberately separate from [VoiceSessionNotifier]: a
/// heartbeat, MessageBus reconnect, or API-only test must not import a media
/// SDK. It also makes the server-selected `mesh`/`livekit` transport explicit.
class VoiceMediaNotifier extends Notifier<VoiceMediaState> {
  VoiceMediaTransport? _transport;
  int _revision = 0;

  @override
  VoiceMediaState build() {
    ref.listen<VoiceSessionState>(
      voiceSessionProvider,
      (previous, next) => unawaited(_sync(previous, next)),
      fireImmediately: true,
    );
    ref.onDispose(() {
      _revision++;
      final transport = _transport;
      _transport = null;
      if (transport != null) unawaited(transport.dispose());
    });
    return const VoiceMediaState();
  }

  Future<void> _sync(
    VoiceSessionState? previous,
    VoiceSessionState session,
  ) async {
    final revision = ++_revision;

    if (!session.isConnected || session.room == null) {
      await _disposeTransport();
      if (revision != _revision) return;
      state = const VoiceMediaState();
      return;
    }

    final sameTransport =
        state.roomId == session.roomId &&
        state.transport == session.transport &&
        _transport != null;
    if (sameTransport) {
      if (!identical(previous?.participants, session.participants)) {
        await _transport!.updateParticipants(session.participants);
      }
      return;
    }

    await _disposeTransport();
    if (revision != _revision) return;

    final currentUser = ref.read(currentUserProvider).value;
    if (currentUser == null) {
      state = VoiceMediaState(
        phase: VoiceMediaPhase.error,
        roomId: session.roomId,
        transport: session.transport,
        error: StateError('Voice media requires an authenticated user'),
      );
      return;
    }

    if (session.usesLiveKit) {
      // The transport boundary and credential refresh path are ready, but
      // livekit_client 2.12.0 pins flutter_webrtc 1.6.0 exactly while Fluxdo
      // needs the 1.6.2 desktop crash hotfix. Do not silently force an unsafe
      // dependency override; keep the server session alive and surface this as
      // an explicit media capability until the SDK combination is validated.
      state = VoiceMediaState(
        phase: VoiceMediaPhase.unsupported,
        roomId: session.roomId,
        transport: session.transport,
      );
      return;
    }

    if (!session.usesMesh) {
      state = VoiceMediaState(
        phase: VoiceMediaPhase.unsupported,
        roomId: session.roomId,
        transport: session.transport,
      );
      return;
    }

    final sessionNotifier = ref.read(voiceSessionProvider.notifier);
    final transport = MeshVoiceTransport(
      VoiceMediaContext(
        room: session.room!,
        currentUserId: currentUser.id,
        participants: session.participants,
        ice: session.ice,
        signals: sessionNotifier.signals,
        sendSignal: sessionNotifier.sendSignal,
      ),
    );
    _transport = transport;
    state = VoiceMediaState(
      phase: VoiceMediaPhase.connecting,
      roomId: session.roomId,
      transport: session.transport,
    );

    try {
      await transport.connect();
      if (revision != _revision || !identical(_transport, transport)) {
        await transport.dispose();
        return;
      }
      state = VoiceMediaState(
        phase: VoiceMediaPhase.connected,
        roomId: session.roomId,
        transport: session.transport,
        muted: transport.muted,
      );
    } catch (e) {
      if (revision != _revision || !identical(_transport, transport)) return;
      await _disposeTransport();
      state = VoiceMediaState(
        phase: VoiceMediaPhase.error,
        roomId: session.roomId,
        transport: session.transport,
        error: e,
      );
    }
  }

  Future<void> setMuted(bool muted) async {
    final transport = _transport;
    if (transport == null || !state.connected || state.muted == muted) return;

    final previous = state.muted;
    await transport.setMuted(muted);
    state = VoiceMediaState(
      phase: state.phase,
      roomId: state.roomId,
      transport: state.transport,
      muted: muted,
    );

    try {
      await ref.read(voiceSessionProvider.notifier).updateState(muted: muted);
    } catch (_) {
      await transport.setMuted(previous);
      state = VoiceMediaState(
        phase: state.phase,
        roomId: state.roomId,
        transport: state.transport,
        muted: previous,
      );
      rethrow;
    }
  }

  Future<void> _disposeTransport() async {
    final transport = _transport;
    _transport = null;
    if (transport != null) await transport.dispose();
  }
}

final voiceMediaProvider =
    NotifierProvider<VoiceMediaNotifier, VoiceMediaState>(
      VoiceMediaNotifier.new,
    );
