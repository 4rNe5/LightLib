import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:openlib/services/network_error.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NetworkError Tests', () {
    test('a bare HTTP 403 is a refusal, not a DDoS challenge', () {
      // A bare 403 (Anna's Archive download mirrors answer "Link expired
      // or invalid..." like this) must not promise the user a captcha
      // solve. The solver must only run for corroborated challenges.
      final dioException = DioException(
        requestOptions: RequestOptions(path: 'https://yqrii5.org/search?q=Flutter'),
        response: Response(
          requestOptions: RequestOptions(path: 'https://yqrii5.org/search?q=Flutter'),
          statusCode: 403,
          data: 'Link expired or invalid. Get a new link to continue.',
        ),
        type: DioExceptionType.badResponse,
      );

      final networkError = NetworkError.fromException(dioException);
      expect(networkError.type, equals(NetworkErrorType.forbidden));
      expect(networkError.userMessage, isNot(contains('captcha')));
    });

    test('a corroborated 403 challenge is cloudflareBlock with its URL', () {
      final dioException = DioException(
        requestOptions: RequestOptions(path: 'https://annas-archive.pk/search?q=Flutter'),
        response: Response(
          requestOptions: RequestOptions(path: 'https://annas-archive.pk/search?q=Flutter'),
          statusCode: 403,
          data: '<title>Just a moment...</title> challenges.cloudflare.com',
        ),
        type: DioExceptionType.badResponse,
      );

      final networkError = NetworkError.fromException(dioException);
      expect(networkError.type, equals(NetworkErrorType.cloudflareBlock));
      expect(networkError.blockedUrl,
          equals('https://annas-archive.pk/search?q=Flutter'));
      expect(networkError.userMessage, contains('DDoS'));
    });

    test("HTTP 52x is the providers' own block page, solver applies", () {
      // 52x codes only exist for these protection providers.
      final dioException = DioException(
        requestOptions: RequestOptions(path: 'https://wbilib.org/search'),
        response: Response(
          requestOptions: RequestOptions(path: 'https://wbilib.org/search'),
          statusCode: 521,
          data: '',
        ),
        type: DioExceptionType.badResponse,
      );

      final networkError = NetworkError.fromException(dioException);
      expect(networkError.type, equals(NetworkErrorType.cloudflareBlock));
    });

    test('Identifies HTTP 451 as forbidden / regional block', () {
      final dioException = DioException(
        requestOptions: RequestOptions(path: 'https://welib.org/search'),
        response: Response(
          requestOptions: RequestOptions(path: 'https://welib.org/search'),
          statusCode: 451,
          data: 'Unavailable For Legal Reasons',
        ),
        type: DioExceptionType.badResponse,
      );

      final networkError = NetworkError.fromException(dioException);
      expect(networkError.type, equals(NetworkErrorType.forbidden));
      expect(networkError.userMessage, contains('region'));
    });

    test('Identifies timeout errors correctly', () {
      final dioException = DioException(
        requestOptions: RequestOptions(path: 'https://annas-archive.gd/search'),
        type: DioExceptionType.connectionTimeout,
        message: 'Connection timeout',
      );

      final networkError = NetworkError.fromException(dioException);
      expect(networkError.type, equals(NetworkErrorType.timeout));
    });
  });
}
