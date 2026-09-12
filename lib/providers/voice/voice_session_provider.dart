import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/voice/voice_event.dart';
import '../../models/voice/voice_room.dart';
import '../../services/message_bus_service.dart';
import '../discourse_providers.dart';
import '../message_bus/message_bus_service_provider.dart';
import '../message_bus/topic_tracking_providers.dart';
import 'voice_rooms_provider.dart';

enum VoiceSessionPhase { idle, joining, connected, leaving, kicked, error }

class VoiceSessionState {
  const VoiceSessionState({
    this.phase = VoiceSessionPhase.idle,
    this.room,
    this.transport,
    this.participantSessionId,
    this.participants = const [],
    this.lastHandRaise,
    this.lastRinging,
    this.heartbeatFailures = 0,
    this.error,
  });

  final VoiceSessionPhase phase;
  final VoiceRoom? room;
  final String? transport;
  final String? participantSessionId;
  final List<VoiceParticipant> participants;
  final VoiceHandRaiseEvent? lastHandRaise;
  final VoiceRingingEvent? lastRinging;
  final int heartbeatFailures;
  final Object? error;

  bool get isConnected => phase == VoiceSessionPhase.connected;
  bool get isBusy =>
      phase == VoiceSessionPhase.joining || phase == VoiceSessionPhase.leaving;
  int? get roomId => room?.id;
  bool get usesMesh => transport == 'mesh';
  bool get usesLiveKit => transport == 'livekit';

  VoiceSessionState copyWith({
    VoiceSessionPhase? phase,
    VoiceRoom? room,
    String? transport,
    String? participantSessionId,
    List<VoiceParticipant>? participants,
    VoiceHandRaiseEvent? lastHandRaise,
    VoiceRingingEvent? lastRinging,
    int? heartbeatFailures,
    Object? error,
    bool clearError = false,
  }) {
    return VoiceSessionState(
      phase: phase ?? this.phase,
      room: room ?? this.room,
      transport: transport ?? this.transport,
      participantSessionId:
          participantSessionId ?? this.participantSessionId,
      participants: participants ?? this.participants,
      lastHandRaise: lastHandRaise ?? this.lastHandRaise,
      lastRinging: lastRinging ?? this.lastRinging,
      heartbeatFailures: heartbeatFailures ?? this.heartbeatFailures,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Owns the single active Voice call in the app.
///
/// The server-issued participant session is the authority for heartbeat,
/// state, and mesh signaling. Presence TTL is 30 seconds server-side; matching
/// the official client, Fluxdo refreshes it every 10 seconds.
class VoiceSessionNotifier extends Notifier<VoiceSessionState> {
  static const _heartbeatInterval = Duration(seconds: 10);

  MessageBusService? _bus;
  MessageBusCallback? _roomCallback;
  Timer? _heartbeatTimer;
  bool _heartbeatInFlight = false;
  int _revision = 0;

  final StreamController<VoiceSignalEvent> _signalController =
      StreamController<VoiceSignalEvent>.broadcast(sync: true);

  Stream<VoiceSignalEvent> get signals => _signalController.stream;

  @override
  VoiceSessionState build() {
    ref.watch(messageBusInitProvider);
    _stopHeartbeat();
    _unsubscribeRoom();
    ref.onDispose(() {
      _revision++;
      _stopHeartbeat();
      _unsubscribeRoom();
      _signalController.close();
    });
    return const VoiceSessionState();
  }

  Future<void> join(
    Object room, {
    String? invitedBy,
    bool skipStatus = false,
  }) async {
    final service = ref.read(discourseServiceProvider);
    if (!service.isVoiceEnabled) return;

    final requestedRoomId = room is int ? room : null;
    if (state.isConnected &&
        requestedRoomId != null &&
        state.roomId == requestedRoomId) {
      return;
    }

    final revision = ++_revision;
    await _leaveCurrent(sendRequest: true);
    if (revision != _revision) return;

    state = VoiceSessionState(
      phase: VoiceSessionPhase.joining,
      room: state.room,
    );

    try {
      final response = await service.joinVoiceRoom(
        room,
        invitedBy: invitedBy,
        skipStatus: skipStatus,
      );

      if (revision != _revision) {
        unawaited(
          service.leaveVoiceRoom(
            response.room.id,
            participantSessionId: response.participantSessionId,
          ),
        );
        return;
      }

      _subscribeRoom(response.room);
      state = VoiceSessionState(
        phase: VoiceSessionPhase.connected,
        room: response.room,
        transport: response.transport,
        participantSessionId: response.participantSessionId,
        participants: response.room.activeParticipants,
      );
      _startHeartbeat();

      // Keep the directory snapshot fresh without waiting for its anonymous-
      // scope broadcast, which intentionally omits manager-only fields.
      ref.read(voiceRoomsProvider.notifier).upsertRoom(response.room);
    } catch (e) {
      if (revision != _revision) return;
      _stopHeartbeat();
      _unsubscribeRoom();
      state = VoiceSessionState(
        phase: VoiceSessionPhase.error,
        error: e,
      );
      rethrow;
    }
  }

  Future<void> leave() async {
    ++_revision;
    if (state.phase == VoiceSessionPhase.idle) return;
    state = state.copyWith(phase: VoiceSessionPhase.leaving, clearError: true);
    await _leaveCurrent(sendRequest: true);
    state = const VoiceSessionState();
  }

  Future<void> _leaveCurrent({required bool sendRequest}) async {
    final roomId = state.roomId;
    final sessionId = state.participantSessionId;
    _stopHeartbeat();
    _unsubscribeRoom();

    if (!sendRequest || roomId == null) return;

    try {
      await ref.read(discourseServiceProvider).leaveVoiceRoom(
            roomId,
            participantSessionId: sessionId,
          );
    } catch (e) {
      // Leaving must always complete locally. The server's presence TTL is the
      // fallback for app termination or a failed final request.
      debugPrint('[VoiceSession] leave failed, dropping locally: $e');
    }
  }

  Future<void> updateState({
    bool? muted,
    bool? deafened,
    bool? video,
    bool? screen,
    bool? watching,
    bool? transcribing,
  }) async {
    final roomId = state.roomId;
    final sessionId = state.participantSessionId;
    if (!state.isConnected || roomId == null || sessionId == null) return;

    await ref.read(discourseServiceProvider).updateVoiceState(
          roomId,
          participantSessionId: sessionId,
          muted: muted,
          deafened: deafened,
          video: video,
          screen: screen,
          watching: watching,
          transcribing: transcribing,
        );
  }

  Future<void> requestToSpeak() async {
    final roomId = state.roomId;
    final sessionId = state.participantSessionId;
    if (!state.isConnected || roomId == null || sessionId == null) return;
    await ref.read(discourseServiceProvider).requestVoiceToSpeak(
          roomId,
          participantSessionId: sessionId,
        );
  }

  Future<void> withdrawRequestToSpeak() async {
    final roomId = state.roomId;
    final sessionId = state.participantSessionId;
    if (!state.isConnected || roomId == null || sessionId == null) return;
    await ref.read(discourseServiceProvider).withdrawVoiceRequestToSpeak(
          roomId,
          participantSessionId: sessionId,
        );
  }

  Future<void> sendSignal(Map<String, dynamic> payload) async {
    final roomId = state.roomId;
    final sessionId = state.participantSessionId;
    if (!state.isConnected ||
        !state.usesMesh ||
        roomId == null ||
        sessionId == null) {
      return;
    }
    await ref.read(discourseServiceProvider).sendVoiceSignal(
          roomId,
          participantSessionId: sessionId,
          payload: payload,
        );
  }

  void _subscribeRoom(VoiceRoom room) {
    _unsubscribeRoom();
    final bus = ref.read(messageBusServiceProvider);
    _bus = bus;

    void onRoomMessage(MessageBusMessage message) {
      final raw = message.data;
      if (raw is! Map) return;
      try {
        final event = VoiceRoomEvent.fromJson(Map<String, dynamic>.from(raw));
        if (event.roomId != room.id) return;
        _applyRoomEvent(event);
      } catch (e) {
        debugPrint('[VoiceSession] room event parse failed: $e');
      }
    }

    _roomCallback = onRoomMessage;
    bus.subscribeWithMessageId(
      '/voice/rooms/${room.id}',
      onRoomMessage,
      room.messageBusLastId ?? -1,
    );
  }

  void _applyRoomEvent(VoiceRoomEvent event) {
    switch (event) {
      case VoiceParticipantsEvent():
        state = state.copyWith(
          participants: event.participants,
          clearError: true,
        );
      case VoiceSignalEvent():
        if (!_signalController.isClosed) _signalController.add(event);
      case VoiceKickedEvent():
        _revision++;
        _stopHeartbeat();
        _unsubscribeRoom();
        state = state.copyWith(
          phase: VoiceSessionPhase.kicked,
          participantSessionId: '',
        );
      case VoiceRoleChangeEvent():
        state = state.copyWith(
          participants: state.participants
              .map(
                (participant) => participant.id == event.userId
                    ? _participantWithRole(participant, event.role)
                    : participant,
              )
              .toList(growable: false),
        );
      case VoiceHandRaiseEvent():
        state = state.copyWith(lastHandRaise: event);
      case VoiceRingingEvent():
        state = state.copyWith(lastRinging: event);
      case VoiceUnknownRoomEvent():
        break;
    }
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      unawaited(_heartbeat());
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _heartbeatInFlight = false;
  }

  Future<void> _heartbeat() async {
    if (_heartbeatInFlight) return;
    final roomId = state.roomId;
    final sessionId = state.participantSessionId;
    if (!state.isConnected || roomId == null || sessionId == null) return;

    _heartbeatInFlight = true;
    try {
      await ref.read(discourseServiceProvider).heartbeatVoiceRoom(
            roomId,
            participantSessionId: sessionId,
          );
      if (state.isConnected) {
        state = state.copyWith(heartbeatFailures: 0, clearError: true);
      }
    } catch (e) {
      if (state.isConnected) {
        state = state.copyWith(
          heartbeatFailures: state.heartbeatFailures + 1,
          error: e,
        );
      }
    } finally {
      _heartbeatInFlight = false;
    }
  }

  void _unsubscribeRoom() {
    final roomId = state.roomId;
    final bus = _bus;
    final callback = _roomCallback;
    if (roomId != null && bus != null && callback != null) {
      bus.unsubscribe('/voice/rooms/$roomId', callback);
    }
    _bus = null;
    _roomCallback = null;
  }
}

VoiceParticipant _participantWithRole(
  VoiceParticipant participant,
  String role,
) {
  return VoiceParticipant(
    id: participant.id,
    username: participant.username,
    name: participant.name,
    avatarTemplate: participant.avatarTemplate,
    role: role,
    muted: participant.muted,
    deafened: participant.deafened,
    videoOn: participant.videoOn,
    screenSharing: participant.screenSharing,
    watchingVideo: participant.watchingVideo,
    transcribing: participant.transcribing,
    idleState: participant.idleState,
    handRaisedAt: participant.handRaisedAt,
  );
}

final voiceSessionProvider =
    NotifierProvider<VoiceSessionNotifier, VoiceSessionState>(
      VoiceSessionNotifier.new,
    );
