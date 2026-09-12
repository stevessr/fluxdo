import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/voice/voice_event.dart';
import '../../models/voice/voice_room.dart';
import '../../services/message_bus_service.dart';
import '../discourse_providers.dart';
import '../message_bus/message_bus_service_provider.dart';
import '../message_bus/topic_tracking_providers.dart';

class VoiceRoomsState {
  const VoiceRoomsState({
    this.rooms = const [],
    this.canCreateRoom = false,
  });

  final List<VoiceRoom> rooms;
  final bool canCreateRoom;

  VoiceRoomsState copyWith({
    List<VoiceRoom>? rooms,
    bool? canCreateRoom,
  }) {
    return VoiceRoomsState(
      rooms: rooms ?? this.rooms,
      canCreateRoom: canCreateRoom ?? this.canCreateRoom,
    );
  }
}

/// Voice room directory backed by `/voice/rooms` + `/voice/rooms/index`.
///
/// The initial response carries `index_message_bus_last_id`; subscribing from
/// that exact point avoids the load/subscribe race without replaying an old
/// directory history.
class VoiceRoomsNotifier extends AsyncNotifier<VoiceRoomsState> {
  MessageBusService? _bus;
  MessageBusCallback? _indexCallback;

  @override
  Future<VoiceRoomsState> build() async {
    ref.watch(messageBusInitProvider);
    final service = ref.read(discourseServiceProvider);

    _teardown();
    ref.onDispose(_teardown);

    if (!service.isVoiceEnabled) return const VoiceRoomsState();

    final response = await service.getVoiceRooms();
    final bus = ref.read(messageBusServiceProvider);
    _bus = bus;

    void onDirectoryEvent(MessageBusMessage message) {
      final raw = message.data;
      if (raw is! Map) return;

      try {
        final event = VoiceDirectoryEvent.fromJson(
          Map<String, dynamic>.from(raw),
        );
        _applyDirectoryEvent(event);
      } catch (e) {
        debugPrint('[VoiceRooms] directory event parse failed: $e');
      }
    }

    _indexCallback = onDirectoryEvent;
    bus.subscribeWithMessageId(
      '/voice/rooms/index',
      onDirectoryEvent,
      response.indexMessageBusLastId ?? -1,
    );

    return VoiceRoomsState(
      rooms: response.rooms,
      canCreateRoom: response.canCreateRoom,
    );
  }

  Future<void> refresh() async {
    final service = ref.read(discourseServiceProvider);
    if (!service.isVoiceEnabled) {
      state = const AsyncData(VoiceRoomsState());
      return;
    }

    final response = await service.getVoiceRooms();
    state = AsyncData(
      VoiceRoomsState(
        rooms: response.rooms,
        canCreateRoom: response.canCreateRoom,
      ),
    );
  }

  void _applyDirectoryEvent(VoiceDirectoryEvent event) {
    final current = state.value;
    if (current == null) return;

    final rooms = [...current.rooms];
    final index = rooms.indexWhere((room) => room.id == event.room.id);

    if (event.isDestroyed) {
      if (index >= 0) {
        rooms.removeAt(index);
        state = AsyncData(current.copyWith(rooms: rooms));
      }
      return;
    }

    if (index >= 0) {
      rooms[index] = event.room;
    } else {
      rooms.add(event.room);
    }
    state = AsyncData(current.copyWith(rooms: rooms));
  }

  void upsertRoom(VoiceRoom room) {
    final current = state.value;
    if (current == null) return;
    final rooms = [...current.rooms];
    final index = rooms.indexWhere((candidate) => candidate.id == room.id);
    if (index >= 0) {
      rooms[index] = room;
    } else {
      rooms.add(room);
    }
    state = AsyncData(current.copyWith(rooms: rooms));
  }

  void _teardown() {
    final bus = _bus;
    final callback = _indexCallback;
    if (bus != null && callback != null) {
      bus.unsubscribe('/voice/rooms/index', callback);
    }
    _bus = null;
    _indexCallback = null;
  }
}

final voiceRoomsProvider =
    AsyncNotifierProvider<VoiceRoomsNotifier, VoiceRoomsState>(
      VoiceRoomsNotifier.new,
    );
