import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/network/adapters/adapter_log_metadata.dart';
import 'package:fluxdo/services/network/flux_request_spec.dart';
import 'package:fluxdo/services/network/recovery/policies.dart';
import 'package:fluxdo/services/network/recovery/recovery_coordinator.dart';
import 'package:fluxdo/services/network/recovery/recovery_policy.dart';

void main() {
  group('RhttpInformationalFallbackPolicy', () {
    test('rhttp 103 GET is replayed once with rhttp bypassed', () async {
      final adapter = _EarlyHintsThenOkAdapter();
      final dio = Dio(
        BaseOptions(
          baseUrl: 'https://linux.do',
          validateStatus: (status) =>
              status != null && status >= 200 && status < 400,
        ),
      )..httpClientAdapter = adapter;
      dio.interceptors.add(
        RecoveryCoordinator(
          dio: dio,
          policies: const [RhttpInformationalFallbackPolicy()],
        ),
      );

      final response = await dio.get<dynamic>('/');

      expect(response.statusCode, 200);
      expect(adapter.callCount, 2);
      expect(adapter.skipRhttpFlags, [false, true]);
    });

    test('does not replay protocol upgrades or unsafe methods', () {
      const policy = RhttpInformationalFallbackPolicy();

      expect(policy.canHandle(_failure(101, method: 'GET')), isFalse);
      expect(policy.canHandle(_failure(103, method: 'POST')), isFalse);
    });

    test('does not claim 103 from a non-rhttp adapter', () {
      const policy = RhttpInformationalFallbackPolicy();
      final outcome = _failure(103, method: 'GET', adapter: 'native');

      expect(policy.canHandle(outcome), isFalse);
    });

    test('retry decision only changes the next attempt semantics', () async {
      const policy = RhttpInformationalFallbackPolicy();
      final outcome = _failure(103, method: 'HEAD');

      expect(policy.canHandle(outcome), isTrue);
      final decision = await policy.decide(outcome);

      expect(decision, isA<RecoveryRetry>());
      final retry = decision as RecoveryRetry;
      expect(retry.delay, Duration.zero);
      expect(
        retry.requestExtra,
        containsPair(FluxRequestKeys.skipRhttpAdapter, true),
      );
      expect(
        outcome.error!.requestOptions.spec.skipRhttpAdapter,
        isFalse,
        reason: '策略只描述下一次尝试，不应原地修改失败请求',
      );
    });
  });
}

AttemptOutcome _failure(
  int status, {
  required String method,
  String adapter = 'rhttp',
}) {
  final options = RequestOptions(
    path: '/',
    baseUrl: 'https://linux.do',
    method: method,
  );
  setRequestAdapterLogName(options, adapter);
  final error = DioException.badResponse(
    statusCode: status,
    requestOptions: options,
    response: Response<dynamic>(
      requestOptions: options,
      statusCode: status,
    ),
  );
  return AttemptOutcome.failure(error: error, attemptIndex: 0);
}

class _EarlyHintsThenOkAdapter implements HttpClientAdapter {
  int callCount = 0;
  final List<bool> skipRhttpFlags = <bool>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    skipRhttpFlags.add(options.spec.skipRhttpAdapter);
    final attempt = callCount++;

    if (attempt == 0) {
      setRequestAdapterLogName(options, 'rhttp');
      return ResponseBody.fromString('', 103);
    }

    return ResponseBody.fromString(
      '{"ok":true}',
      200,
      headers: {
        Headers.contentTypeHeader: const ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
