import 'package:flutter_test/flutter_test.dart';
import 'package:villager_translator/domain/common/cancellation_token.dart';
import 'package:villager_translator/domain/llm/llm_api_exception.dart';
import 'package:villager_translator/domain/translation/retry_policy.dart';

void main() {
  group('translateChunkWithRetry', () {
    test('一時的な失敗(タイムアウト・5xx相当)には設定回数までリトライし、成功すれば結果を返す', () async {
      var callCount = 0;
      final waited = <Duration>[];

      final result = await translateChunkWithRetry(
        {'a': '1'},
        translateChunk: (chunk) async {
          callCount++;
          if (callCount < 3) {
            throw const LlmApiException(message: '一時的な障害', statusCode: 500);
          }
          return {'a': 'translated'};
        },
        maxRetries: 3,
        waiter: (d) async {
          waited.add(d);
        },
      );

      expect(result, {'a': 'translated'});
      expect(callCount, 3);
      expect(waited.length, 2);
    });

    test('401相当の認証エラーはリトライせず即座に失敗する', () async {
      var callCount = 0;

      await expectLater(
        translateChunkWithRetry(
          {'a': '1'},
          translateChunk: (chunk) async {
            callCount++;
            throw const LlmApiException(message: '認証エラー', statusCode: 401);
          },
          maxRetries: 3,
          waiter: (_) async {},
        ),
        throwsA(isA<LlmApiException>()),
      );
      expect(callCount, 1);
    });

    test('429相当のレート制限では retry-after 相当の待機時間を尊重してリトライする', () async {
      var callCount = 0;
      final waited = <Duration>[];

      final result = await translateChunkWithRetry(
        {'a': '1'},
        translateChunk: (chunk) async {
          callCount++;
          if (callCount == 1) {
            throw const LlmApiException(
              message: 'レート制限',
              statusCode: 429,
              retryAfter: Duration(seconds: 30),
            );
          }
          return {'a': 'translated'};
        },
        maxRetries: 3,
        waiter: (d) async {
          waited.add(d);
        },
      );

      expect(result, {'a': 'translated'});
      expect(waited, [const Duration(seconds: 30)]);
    });

    test('全リトライ失敗後は最後の例外を再送出する', () async {
      await expectLater(
        translateChunkWithRetry(
          {'a': '1'},
          translateChunk: (chunk) async {
            throw const LlmApiException(message: '常に失敗', statusCode: 500);
          },
          maxRetries: 2,
          waiter: (_) async {},
        ),
        throwsA(isA<LlmApiException>()),
      );
    });
  });

  group('resolveRetryWait', () {
    test('retry-after が判明している場合はその値を返す', () {
      const error = LlmApiException(
        message: 'レート制限',
        statusCode: 429,
        retryAfter: Duration(seconds: 12),
      );

      expect(resolveRetryWait(error, 1), const Duration(seconds: 12));
    });

    test('retry-after が無い場合は試行回数に応じた線形バックオフを返す', () {
      const error = LlmApiException(message: '一時的な障害', statusCode: 500);

      expect(resolveRetryWait(error, 3), const Duration(seconds: 3));
    });
  });

  group('translateChunksWithPartialSuccess', () {
    test('リトライを使い切ったチャンクはスキップし、他のチャンクの処理を継続する', () async {
      final chunks = [
        {'a': '1'},
        {'b': '2'},
        {'c': '3'},
      ];

      final results = await translateChunksWithPartialSuccess(
        chunks,
        translateChunk: (chunk) async {
          if (chunk.containsKey('b')) {
            throw const LlmApiException(message: '常に失敗', statusCode: 500);
          }
          return {
            for (final e in chunk.entries) e.key: '${e.value}_translated',
          };
        },
        maxRetries: 1,
        waiter: (_) async {},
      );

      expect(results, [
        {'a': '1_translated'},
        {'c': '3_translated'},
      ]);
    });

    test('認証エラーが発生した場合はバッチ全体を中断して例外を再送出する', () async {
      var callCount = 0;
      final chunks = [
        {'a': '1'},
        {'b': '2'},
      ];

      await expectLater(
        translateChunksWithPartialSuccess(
          chunks,
          translateChunk: (chunk) async {
            callCount++;
            throw const LlmApiException(message: '認証エラー', statusCode: 401);
          },
          maxRetries: 3,
          waiter: (_) async {},
        ),
        throwsA(isA<LlmApiException>()),
      );
      expect(callCount, 1);
    });

    test('キャンセル済みの場合、実行中のチャンクは完了させた上で以降のチャンクは開始しない', () async {
      final token = CancellationToken();
      final chunks = [
        {'a': '1'},
        {'b': '2'},
        {'c': '3'},
      ];
      var callCount = 0;

      final results = await translateChunksWithPartialSuccess(
        chunks,
        translateChunk: (chunk) async {
          callCount++;
          if (chunk.containsKey('a')) {
            token.cancel();
          }
          return {
            for (final e in chunk.entries) e.key: '${e.value}_translated',
          };
        },
        maxRetries: 1,
        waiter: (_) async {},
        cancellationToken: token,
      );

      expect(callCount, 1);
      expect(results, [
        {'a': '1_translated'},
      ]);
    });

    test('onChunkComplete が成功・失敗を問わずチャンクごとに完了数/総数を通知する', () async {
      final chunks = [
        {'a': '1'},
        {'b': '2'},
      ];
      final progressUpdates = <List<int>>[];

      await translateChunksWithPartialSuccess(
        chunks,
        translateChunk: (chunk) async {
          if (chunk.containsKey('b')) {
            throw const LlmApiException(message: '常に失敗', statusCode: 500);
          }
          return {
            for (final e in chunk.entries) e.key: '${e.value}_translated',
          };
        },
        maxRetries: 1,
        waiter: (_) async {},
        onChunkComplete: (completed, total) =>
            progressUpdates.add([completed, total]),
      );

      expect(progressUpdates, [
        [1, 2],
        [2, 2],
      ]);
    });
  });
}
