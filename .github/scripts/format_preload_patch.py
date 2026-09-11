from pathlib import Path

service_path = Path('lib/services/preloaded_data_service.dart')
test_path = Path('test/services/preloaded_data_progress_test.dart')

service = service_path.read_text()
service = service.replace(
    '''      final totalWorkUnits =
          scanUnits +
          userSettingsUnits +
          siteUnits +
          (topicUnits * 2) +
          1;
''',
    '''      final totalWorkUnits =
          scanUnits + userSettingsUnits + siteUnits + (topicUnits * 2) + 1;
''',
    1,
)
service = service.replace(
    '''        return compute(
          _parseTopicBatchInIsolate,
          <String, dynamic>{
            'users': rawUsers,
            'topics': rawTopics.sublist(start, end),
          },
        );
''',
    '''        return compute(_parseTopicBatchInIsolate, <String, dynamic>{
          'users': rawUsers,
          'topics': rawTopics.sublist(start, end),
        });
''',
    1,
)
service_path.write_text(service)

test = test_path.read_text()
test = test.replace(
    "      expect(serviceSource, contains('for (final start in starts) parseBatch(start)'));\n",
    "      expect(\n"
    "        serviceSource,\n"
    "        contains('for (final start in starts) parseBatch(start)'),\n"
    "      );\n",
    1,
)
test_path.write_text(test)
