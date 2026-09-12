import '../../models/voice/voice_event.dart';
import '../../models/voice/voice_room.dart';

/// Media transport boundary for Discourse Voice.
///
/// The server decides the transport at join time. Mesh and LiveKit therefore
/// share lifecycle/control-plane state, while all SDK-specific media code stays
/// behind this interface.
abstract class VoiceMediaTransport {
  String get name;
  bool get connected;
  bool get muted;

  Future<void> connect();
  Future<void> updateParticipants(List<VoiceParticipant> participants);
  Future<void> setMuted(bool muted);
  Future<void> dispose();
}

/// Immutable inputs shared by concrete Voice media transports.
class VoiceMediaContext {
  const VoiceMediaContext({
    required this.room,
    required this.currentUserId,
    required this.participants,
    required this.sendSignal,
    required this.signals,
    this.ice = const {},
  });

  final VoiceRoom room;
  final int currentUserId;
  final List<VoiceParticipant> participants;
  final Map<String, dynamic> ice;
  final Stream<VoiceSignalEvent> signals;
  final Future<void> Function(Map<String, dynamic> payload) sendSignal;
}
