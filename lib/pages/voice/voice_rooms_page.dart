import 'package:app_icons/app_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/s.dart';
import '../../models/voice/voice_room.dart';
import '../../providers/voice/voice_media_provider.dart';
import '../../providers/voice/voice_rooms_provider.dart';
import '../../providers/voice/voice_session_provider.dart';
import '../../services/toast_service.dart';
import '../../utils/url_helper.dart';
import '../../widgets/common/error_view.dart';
import '../../widgets/common/smart_avatar.dart';

/// Directory for Discourse's built-in Voice core plugin.
class VoiceRoomsPage extends ConsumerWidget {
  const VoiceRoomsPage({super.key, this.isActive = true});

  final bool isActive;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooms = ref.watch(voiceRoomsProvider);
    final session = ref.watch(voiceSessionProvider);
    // Activates the media lifecycle and keeps it alive with this IndexedStack
    // page even when the user switches to another bottom-nav tab.
    final media = ref.watch(voiceMediaProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Voice'),
        actions: [
          IconButton(
            icon: const Icon(Symbols.refresh_rounded),
            tooltip: context.l10n.common_retry,
            onPressed: () => ref.read(voiceRoomsProvider.notifier).refresh(),
          ),
        ],
      ),
      body: rooms.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => ErrorView(
          error: error,
          stackTrace: stackTrace,
          onRetry: () => ref.invalidate(voiceRoomsProvider),
        ),
        data: (directory) {
          return RefreshIndicator(
            onRefresh: () => ref.read(voiceRoomsProvider.notifier).refresh(),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                if (session.phase != VoiceSessionPhase.idle)
                  SliverToBoxAdapter(
                    child: _ActiveSessionCard(
                      session: session,
                      media: media,
                      onToggleMute: media.connected
                          ? () => _toggleMute(context, ref, media)
                          : null,
                    ),
                  ),
                if (directory.rooms.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyVoiceRooms(),
                  )
                else
                  SliverList.separated(
                    itemCount: directory.rooms.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final room = directory.rooms[index];
                      final isCurrentRoom = session.roomId == room.id;
                      final participants = isCurrentRoom && session.isConnected
                          ? session.participants
                          : room.activeParticipants;
                      return _VoiceRoomTile(
                        room: room,
                        participants: participants,
                        session: session,
                        onJoin: () => _join(context, ref, room),
                        onLeave: () => _leave(context, ref),
                      );
                    },
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _join(
    BuildContext context,
    WidgetRef ref,
    VoiceRoom room,
  ) async {
    try {
      await ref.read(voiceSessionProvider.notifier).join(room.id);
    } catch (e) {
      if (!context.mounted) return;
      ToastService.showError(e.toString());
    }
  }

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(voiceSessionProvider.notifier).leave();
    } catch (e) {
      if (!context.mounted) return;
      ToastService.showError(e.toString());
    }
  }

  Future<void> _toggleMute(
    BuildContext context,
    WidgetRef ref,
    VoiceMediaState media,
  ) async {
    try {
      await ref.read(voiceMediaProvider.notifier).setMuted(!media.muted);
    } catch (e) {
      if (!context.mounted) return;
      ToastService.showError(e.toString());
    }
  }
}

class _ActiveSessionCard extends StatelessWidget {
  const _ActiveSessionCard({
    required this.session,
    required this.media,
    this.onToggleMute,
  });

  final VoiceSessionState session;
  final VoiceMediaState media;
  final VoidCallback? onToggleMute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final roomName = session.room?.name ?? 'Voice';
    final warning =
        session.heartbeatFailures > 0 ||
        media.phase == VoiceMediaPhase.error ||
        media.phase == VoiceMediaPhase.unsupported;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: warning
            ? theme.colorScheme.errorContainer.withValues(alpha: 0.45)
            : theme.colorScheme.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(
            warning ? Symbols.signal_wifi_off_rounded : Symbols.mic_rounded,
            color: warning
                ? theme.colorScheme.error
                : theme.colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  roomName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _sessionStatus(session, media),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (session.isConnected) ...[
            Text(
              session.transport ?? '',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (onToggleMute != null)
            IconButton.filledTonal(
              tooltip: media.muted ? 'Unmute' : 'Mute',
              onPressed: onToggleMute,
              icon: Icon(
                media.muted ? Symbols.mic_off_rounded : Symbols.mic_rounded,
              ),
            ),
        ],
      ),
    );
  }

  String _sessionStatus(
    VoiceSessionState session,
    VoiceMediaState media,
  ) {
    switch (session.phase) {
      case VoiceSessionPhase.idle:
        return '';
      case VoiceSessionPhase.joining:
        return 'Connecting…';
      case VoiceSessionPhase.connected:
        if (session.heartbeatFailures > 0) {
          return 'Control plane reconnecting (${session.heartbeatFailures})…';
        }
        switch (media.phase) {
          case VoiceMediaPhase.idle:
          case VoiceMediaPhase.connecting:
            return 'Connecting media…';
          case VoiceMediaPhase.connected:
            return '${session.participants.length} connected';
          case VoiceMediaPhase.unsupported:
            return session.usesLiveKit
                ? 'LiveKit media is not enabled in this draft build'
                : 'Unsupported Voice media transport';
          case VoiceMediaPhase.error:
            return 'Media connection failed';
        }
      case VoiceSessionPhase.leaving:
        return 'Leaving…';
      case VoiceSessionPhase.kicked:
        return 'Disconnected by room moderator';
      case VoiceSessionPhase.error:
        return 'Connection failed';
    }
  }
}

class _VoiceRoomTile extends StatelessWidget {
  const _VoiceRoomTile({
    required this.room,
    required this.participants,
    required this.session,
    required this.onJoin,
    required this.onLeave,
  });

  final VoiceRoom room;
  final List<VoiceParticipant> participants;
  final VoiceSessionState session;
  final VoidCallback onJoin;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCurrentRoom = session.roomId == room.id;
    final connectedHere = isCurrentRoom && session.isConnected;
    final busyHere = isCurrentRoom && session.isBusy;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        leading: _RoomIcon(room: room),
        title: Text(
          room.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: connectedHere ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (room.descriptionExcerpt?.isNotEmpty == true) ...[
                Text(
                  room.descriptionExcerpt!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  _ParticipantStack(participants: participants),
                  if (participants.isNotEmpty) const SizedBox(width: 8),
                  Text(
                    room.maxParticipants > 0
                        ? '${participants.length}/${room.maxParticipants}'
                        : '${participants.length}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (room.roomType == 'stage') ...[
                    const SizedBox(width: 8),
                    Icon(
                      Symbols.campaign_rounded,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                  if (!room.isPublic) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Symbols.lock_rounded,
                      size: 15,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        trailing: busyHere
            ? const SizedBox.square(
                dimension: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : connectedHere
            ? FilledButton.tonal(
                onPressed: onLeave,
                child: Text(context.l10n.chat_leave),
              )
            : FilledButton(
                onPressed: session.isBusy ? null : onJoin,
                child: Text(context.l10n.chat_joinChannel),
              ),
      ),
    );
  }
}

class _RoomIcon extends StatelessWidget {
  const _RoomIcon({required this.room});

  final VoiceRoom room;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: Icon(
        room.roomType == 'stage'
            ? Symbols.campaign_rounded
            : Symbols.graphic_eq_rounded,
        color: theme.colorScheme.onSecondaryContainer,
      ),
    );
  }
}

class _ParticipantStack extends StatelessWidget {
  const _ParticipantStack({required this.participants});

  final List<VoiceParticipant> participants;

  @override
  Widget build(BuildContext context) {
    final visible = participants.take(4).toList(growable: false);
    if (visible.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      width: 20.0 + (visible.length - 1) * 14,
      height: 22,
      child: Stack(
        children: [
          for (var index = 0; index < visible.length; index++)
            Positioned(
              left: index * 14,
              child: SmartAvatar(
                imageUrl: _avatarUrl(visible[index]),
                fallbackText: visible[index].username,
                radius: 11,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: 1.5,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String? _avatarUrl(VoiceParticipant participant) {
    final template = participant.avatarTemplate;
    if (template == null || template.isEmpty) return null;
    return UrlHelper.resolveUrlWithCdn(template.replaceAll('{size}', '64'));
  }
}

class _EmptyVoiceRooms extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Symbols.graphic_eq_rounded,
              size: 52,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.chat_noChannelsFound,
              style: theme.textTheme.titleMedium,
            ),
          ],
        ),
      ),
    );
  }
}
