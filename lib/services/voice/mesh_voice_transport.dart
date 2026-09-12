import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../models/voice/voice_event.dart';
import '../../models/voice/voice_room.dart';
import 'voice_media_transport.dart';

/// Voice-only mesh transport compatible with Discourse Voice signaling.
///
/// One RTCPeerConnection is maintained per remote participant. As in the
/// official client, the lower user id initiates the normal offer to avoid
/// glare. Candidate/HTTP batching mirrors the server's documented limits so a
/// Trickle ICE burst does not turn into dozens of HTTP requests.
class MeshVoiceTransport implements VoiceMediaTransport {
  MeshVoiceTransport(this.context);

  static const _candidateBatchDelay = Duration(milliseconds: 75);
  static const _candidateBatchSize = 5;
  static const _httpBatchDelay = Duration(milliseconds: 200);
  static const _httpFlushEventThreshold = 20;

  final VoiceMediaContext context;

  final Map<int, _MeshPeer> _peers = {};
  final Map<int, List<Map<String, dynamic>>> _orphanCandidates = {};
  final Map<int, List<Map<String, dynamic>>> _candidateQueues = {};
  final Map<int, Timer> _candidateTimers = {};
  final Map<int, List<Map<String, dynamic>>> _httpQueues = {};
  final Map<int, MediaStream> _remoteStreams = {};

  StreamSubscription<VoiceSignalEvent>? _signalSubscription;
  Timer? _httpTimer;
  MediaStream? _localStream;
  List<VoiceParticipant> _participants = const [];
  Future<void> _signalTail = Future.value();
  bool _connected = false;
  bool _disposed = false;
  bool _muted = false;
  bool _canPublishAudio = false;

  @override
  String get name => 'mesh';

  @override
  bool get connected => _connected;

  @override
  bool get muted => _muted;

  Map<int, MediaStream> get remoteStreams =>
      Map<int, MediaStream>.unmodifiable(_remoteStreams);

  @override
  Future<void> connect() async {
    if (_disposed || _connected) return;

    _participants = context.participants;
    _canPublishAudio = _localCanSpeak(_participants);
    if (_canPublishAudio) await _ensureLocalAudio();

    _signalSubscription = context.signals.listen((event) {
      if (_disposed || event.roomId != context.room.id) return;
      _signalTail = _signalTail.then((_) => _handleSignal(event)).catchError(
        (Object error, StackTrace stackTrace) {
          debugPrint('[VoiceMesh] signal handling failed: $error');
        },
      );
    });

    _connected = true;
    await _reconcilePeers();
  }

  @override
  Future<void> updateParticipants(List<VoiceParticipant> participants) async {
    if (_disposed) return;
    final couldPublish = _canPublishAudio;
    _participants = List<VoiceParticipant>.unmodifiable(participants);
    _canPublishAudio = _localCanSpeak(_participants);

    if (_connected && couldPublish != _canPublishAudio) {
      if (_canPublishAudio) {
        await _ensureLocalAudio();
      } else {
        await _disposeLocalAudio();
      }
      await _destroyAllPeers();
    }

    if (_connected) await _reconcilePeers();
  }

  @override
  Future<void> setMuted(bool muted) async {
    if (_disposed) return;
    _muted = muted;
    if (!_canPublishAudio) return;

    await _ensureLocalAudio();
    for (final track in _localStream?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = !muted;
    }
  }

  Future<void> _ensureLocalAudio() async {
    if (_localStream != null || !_canPublishAudio || _disposed) return;

    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    });
    for (final track in stream.getAudioTracks()) {
      track.enabled = !_muted;
    }
    if (_disposed || !_canPublishAudio) {
      await stream.dispose();
      return;
    }
    _localStream = stream;
  }

  Future<void> _reconcilePeers() async {
    if (_disposed || !_connected) return;

    final desired = <int, VoiceParticipant>{};
    for (final participant in _participants) {
      if (participant.id == context.currentUserId || participant.id <= 0) continue;
      if (_shouldMaintainPeer(participant)) desired[participant.id] = participant;
    }

    for (final remoteId in _peers.keys.toList(growable: false)) {
      if (!desired.containsKey(remoteId)) await _destroyPeer(remoteId);
    }

    for (final participant in desired.values) {
      final existed = _peers.containsKey(participant.id);
      await _ensurePeer(participant.id);
      if (!existed && context.currentUserId < participant.id) {
        await _initiateOffer(participant.id);
      }
    }
  }

  bool _localCanSpeak(List<VoiceParticipant> participants) {
    if (context.room.roomType != 'stage') return true;
    String? role = context.room.membership?.role;
    for (final participant in participants) {
      if (participant.id == context.currentUserId) {
        role = participant.role;
        break;
      }
    }
    return role == 'moderator' || role == 'speaker';
  }

  bool _shouldMaintainPeer(VoiceParticipant remote) {
    if (context.room.roomType != 'stage') return true;
    final theyCanSpeak = remote.role == 'moderator' || remote.role == 'speaker';
    return _canPublishAudio || theyCanSpeak;
  }

  Future<_MeshPeer?> _ensurePeer(int remoteUserId) async {
    if (_disposed || remoteUserId == context.currentUserId) return null;
    final existing = _peers[remoteUserId];
    if (existing != null) return existing;

    final pc = await createPeerConnection(_peerConfiguration());
    final peer = _MeshPeer(pc);
    _peers[remoteUserId] = peer;

    pc.onIceCandidate = (candidate) {
      final text = candidate.candidate;
      if (_disposed || text == null || text.isEmpty) {
        if (text == null || text.isEmpty) {
          unawaited(_flushCandidateQueue(remoteUserId));
        }
        return;
      }
      _queueCandidate(remoteUserId, {
        'type': 'candidate',
        'candidate': {
          'candidate': text,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      });
    };

    pc.onIceGatheringState = (state) {
      if (state.toString().toLowerCase().contains('complete')) {
        unawaited(_flushCandidateQueue(remoteUserId));
      }
    };

    pc.onTrack = (event) {
      if (_disposed || event.track.kind != 'audio' || event.streams.isEmpty) return;
      _remoteStreams[remoteUserId] = event.streams.first;
    };

    final local = _localStream;
    if (_canPublishAudio && local != null) {
      for (final track in local.getAudioTracks()) {
        await pc.addTrack(track, local);
      }
    }

    final orphaned = _orphanCandidates.remove(remoteUserId);
    if (orphaned != null) peer.pendingCandidates.addAll(orphaned);
    return peer;
  }

  Map<String, dynamic> _peerConfiguration() {
    final servers = context.ice['servers'];
    final transportPolicy = context.ice['transport_policy']?.toString();
    return {
      'sdpSemantics': 'unified-plan',
      'iceServers': servers is List ? servers : const [],
      if (transportPolicy == 'relay' || transportPolicy == 'all')
        'iceTransportPolicy': transportPolicy,
    };
  }

  Future<void> _initiateOffer(int remoteUserId) async {
    final peer = _peers[remoteUserId];
    if (peer == null || _disposed) return;

    final localDescription = await peer.pc.getLocalDescription();
    if (localDescription?.type == 'offer') return;

    final offer = await peer.pc.createOffer({
      'mandatory': {
        'OfferToReceiveAudio': true,
        'OfferToReceiveVideo': false,
      },
      'optional': [],
    });
    await peer.pc.setLocalDescription(offer);
    await _sendEvent(remoteUserId, {
      'type': offer.type,
      'sdp': offer.sdp,
    });
  }

  Future<void> _handleSignal(VoiceSignalEvent envelope) async {
    final remoteUserId = envelope.senderId;
    if (_disposed || remoteUserId <= 0 || remoteUserId == context.currentUserId) return;

    for (final data in envelope.events) {
      final type = data['type']?.toString();
      if (type == null) continue;

      if (!_peers.containsKey(remoteUserId) && type == 'candidate') {
        final candidate = data['candidate'];
        if (candidate is Map && context.room.roomType != 'stage') {
          (_orphanCandidates[remoteUserId] ??= []).add(
            Map<String, dynamic>.from(candidate),
          );
        }
        continue;
      }

      VoiceParticipant? knownRemote;
      for (final participant in _participants) {
        if (participant.id == remoteUserId) {
          knownRemote = participant;
          break;
        }
      }
      if (knownRemote == null && type != 'offer' && type != 'candidate') continue;
      if (knownRemote == null && context.room.roomType == 'stage') continue;
      if (knownRemote != null && !_shouldMaintainPeer(knownRemote)) continue;

      var peer = await _ensurePeer(remoteUserId);
      if (peer == null) continue;

      switch (type) {
        case 'offer':
          final sdp = data['sdp']?.toString();
          if (sdp == null || sdp.isEmpty) continue;

          final local = await peer.pc.getLocalDescription();
          if (local?.type == 'offer') {
            if (context.currentUserId < remoteUserId) {
              await _destroyPeer(remoteUserId);
              peer = await _ensurePeer(remoteUserId);
              if (peer == null) continue;
            } else {
              continue;
            }
          }

          await peer.pc.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
          await _flushPendingCandidates(peer);
          final answer = await peer.pc.createAnswer({
            'mandatory': {
              'OfferToReceiveAudio': true,
              'OfferToReceiveVideo': false,
            },
            'optional': [],
          });
          await peer.pc.setLocalDescription(answer);
          await _sendEvent(remoteUserId, {
            'type': answer.type,
            'sdp': answer.sdp,
          });

        case 'answer':
          final sdp = data['sdp']?.toString();
          if (sdp == null || sdp.isEmpty) continue;
          final local = await peer.pc.getLocalDescription();
          if (local?.type != 'offer') continue;
          await peer.pc.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
          await _flushPendingCandidates(peer);

        case 'candidate':
          final rawCandidate = data['candidate'];
          if (rawCandidate is! Map) continue;
          final candidate = Map<String, dynamic>.from(rawCandidate);
          if (await peer.pc.getRemoteDescription() == null) {
            peer.pendingCandidates.add(candidate);
          } else {
            await _addCandidate(peer.pc, candidate);
          }
      }
    }
  }

  Future<void> _flushPendingCandidates(_MeshPeer peer) async {
    if (peer.pendingCandidates.isEmpty) return;
    final queued = List<Map<String, dynamic>>.from(peer.pendingCandidates);
    peer.pendingCandidates.clear();
    for (final candidate in queued) {
      await _addCandidate(peer.pc, candidate);
    }
  }

  Future<void> _addCandidate(
    RTCPeerConnection pc,
    Map<String, dynamic> candidate,
  ) async {
    final text = candidate['candidate']?.toString();
    if (text == null || text.isEmpty) return;
    final indexRaw = candidate['sdpMLineIndex'];
    final index = indexRaw is num
        ? indexRaw.toInt()
        : int.tryParse(indexRaw?.toString() ?? '');
    await pc.addCandidate(
      RTCIceCandidate(text, candidate['sdpMid']?.toString(), index),
    );
  }

  void _queueCandidate(int remoteUserId, Map<String, dynamic> event) {
    final queue = _candidateQueues[remoteUserId] ??= [];
    queue.add(event);
    if (queue.length >= _candidateBatchSize) {
      unawaited(_flushCandidateQueue(remoteUserId));
      return;
    }
    _candidateTimers[remoteUserId]?.cancel();
    _candidateTimers[remoteUserId] = Timer(_candidateBatchDelay, () {
      _candidateTimers.remove(remoteUserId);
      unawaited(_flushCandidateQueue(remoteUserId));
    });
  }

  Future<void> _flushCandidateQueue(int remoteUserId) async {
    _candidateTimers.remove(remoteUserId)?.cancel();
    final queue = _candidateQueues.remove(remoteUserId);
    if (queue == null || queue.isEmpty || _disposed) return;
    await _enqueueHttp(remoteUserId, queue);
  }

  Future<void> _sendEvent(int remoteUserId, Map<String, dynamic> event) async {
    await _flushCandidateQueue(remoteUserId);
    await _enqueueHttp(remoteUserId, [event]);
  }

  Future<void> _enqueueHttp(
    int remoteUserId,
    List<Map<String, dynamic>> events,
  ) async {
    if (_disposed || events.isEmpty || !_peers.containsKey(remoteUserId)) return;
    final queue = _httpQueues[remoteUserId] ??= [];
    queue.addAll(events);

    if (queue.length >= _httpFlushEventThreshold) {
      _httpTimer?.cancel();
      _httpTimer = null;
      await _flushHttp();
      return;
    }

    _httpTimer ??= Timer(_httpBatchDelay, () {
      _httpTimer = null;
      unawaited(_flushHttp());
    });
  }

  Future<void> _flushHttp() async {
    if (_disposed || _httpQueues.isEmpty) return;
    final snapshot = <int, List<Map<String, dynamic>>>{};
    for (final entry in _httpQueues.entries) {
      if (_peers.containsKey(entry.key) && entry.value.isNotEmpty) {
        snapshot[entry.key] = List<Map<String, dynamic>>.from(entry.value);
      }
    }
    _httpQueues.clear();
    if (snapshot.isEmpty) return;

    final messages = snapshot.entries
        .map((entry) => <String, dynamic>{
              'recipient_id': entry.key,
              'events': entry.value,
            })
        .toList(growable: false);

    final Map<String, dynamic> payload;
    if (messages.length == 1) {
      final message = messages.single;
      final events = message['events']! as List<Map<String, dynamic>>;
      if (events.length == 1) {
        payload = {
          ...events.single,
          'recipient_id': message['recipient_id'],
        };
      } else {
        payload = message;
      }
    } else {
      payload = {'messages': messages};
    }

    await context.sendSignal(payload);
  }

  Future<void> _destroyPeer(int remoteUserId) async {
    _candidateTimers.remove(remoteUserId)?.cancel();
    _candidateQueues.remove(remoteUserId);
    _httpQueues.remove(remoteUserId);
    _orphanCandidates.remove(remoteUserId);
    _remoteStreams.remove(remoteUserId);

    final peer = _peers.remove(remoteUserId);
    if (peer == null) return;
    peer.pc.onIceCandidate = null;
    peer.pc.onTrack = null;
    peer.pc.onIceGatheringState = null;
    await peer.pc.close();
    await peer.pc.dispose();
  }

  Future<void> _destroyAllPeers() async {
    for (final remoteId in _peers.keys.toList(growable: false)) {
      await _destroyPeer(remoteId);
    }
  }

  Future<void> _disposeLocalAudio() async {
    final stream = _localStream;
    _localStream = null;
    if (stream == null) return;
    for (final track in stream.getTracks()) {
      await track.stop();
    }
    await stream.dispose();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _connected = false;

    await _signalSubscription?.cancel();
    _signalSubscription = null;
    _httpTimer?.cancel();
    _httpTimer = null;
    for (final timer in _candidateTimers.values) {
      timer.cancel();
    }
    _candidateTimers.clear();
    _candidateQueues.clear();
    _httpQueues.clear();
    _orphanCandidates.clear();

    await _destroyAllPeers();
    await _disposeLocalAudio();
    _remoteStreams.clear();
  }
}

class _MeshPeer {
  _MeshPeer(this.pc);

  final RTCPeerConnection pc;
  final List<Map<String, dynamic>> pendingCandidates = [];
}
