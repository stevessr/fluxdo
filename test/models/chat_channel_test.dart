import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/chat/chat_channel.dart';

void main() {
  group('ChatChannel Retention & Parsing Tests', () {
    test('parse numeric retention_days', () {
      final json = {'id': 1, 'retention_days': 30};
      final channel = ChatChannel.fromJson(json);
      expect(channel.retentionDays, equals(30));
      expect(channel.retentionDisplay, equals('30 天'));
    });

    test('parse auto_delete_preference string "90_days"', () {
      final json = {'id': 2, 'auto_delete_preference': '90_days'};
      final channel = ChatChannel.fromJson(json);
      expect(channel.retentionDays, equals(90));
      expect(channel.retentionDisplay, equals('90 天'));
    });

    test('parse auto_delete_preference string "24_hours"', () {
      final json = {'id': 3, 'auto_delete_preference': '24_hours'};
      final channel = ChatChannel.fromJson(json);
      expect(channel.retentionHours, equals(24));
      expect(channel.retentionDisplay, equals('24 小时'));
    });

    test('parse auto_delete_days in meta', () {
      final json = {
        'id': 4,
        'meta': {'auto_delete_days': 7}
      };
      final channel = ChatChannel.fromJson(json);
      expect(channel.retentionDays, equals(7));
      expect(channel.retentionDisplay, equals('7 天'));
    });

    test('parse never auto delete', () {
      final json = {'id': 5, 'auto_delete_preference': 'never'};
      final channel = ChatChannel.fromJson(json);
      expect(channel.retentionDays, isNull);
      expect(channel.retentionHours, isNull);
      expect(channel.retentionDisplay, equals('永久保留'));
    });
  });
}
