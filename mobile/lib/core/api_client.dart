import 'package:dio/dio.dart';

/// Error surfaced after mapping raw Dio/network failures to a friendly
/// message that can be shown directly in the UI.
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  const ApiException(this.message, {this.statusCode});

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

/// Thin HTTP client over Dio. Adds the Bearer token on every request and
/// normalizes failures into [ApiException].
class ApiClient {
  final String baseUrl;
  final Dio _dio;
  String? _token;

  ApiClient(this.baseUrl) : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 12),
            receiveTimeout: const Duration(seconds: 20),
            headers: {'Accept': 'application/json'},
          ),
        ) {
    _dio.interceptors.add(
      InterceptorsWrapper(onRequest: (options, handler) {
        if (_token != null) {
          options.headers['Authorization'] = 'Bearer $_token';
        }
        handler.next(options);
      }),
    );
  }

  void setToken(String? token) => _token = token;

  /// The currently held Bearer token (used by WebSocket auth, which cannot
  /// send headers — it authenticates via `?token=` instead).
  String? get token => _token;

  Future<Map<String, dynamic>> get(String path,
      {Map<String, dynamic>? query}) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(path, queryParameters: query);
      return res.data ?? const {};
    } on DioException catch (e) {
      throw _mapDio(e);
    }
  }

  Future<Map<String, dynamic>> post(String path,
      {Map<String, dynamic>? data}) async {
    return _send(() => _dio.post<Map<String, dynamic>>(path, data: data));
  }

  Future<Map<String, dynamic>> patch(String path,
      {Map<String, dynamic>? data}) async {
    return _send(() => _dio.patch<Map<String, dynamic>>(path, data: data));
  }

  Future<Map<String, dynamic>> delete(String path) async {
    return _send(() => _dio.delete<Map<String, dynamic>>(path));
  }

  /// Multipart file upload (profile avatar). Returns the parsed JSON body.
  Future<Map<String, dynamic>> uploadFile(
      String path, String field, String filePath,
      {String contentType = 'image/jpeg'}) async {
    final form = FormData.fromMap({
      field: await MultipartFile.fromFile(
        filePath,
        filename: filePath.split('/').last,
        contentType: DioMediaType.parse(contentType),
      ),
    });
    return _send(() => _dio.put<Map<String, dynamic>>(path, data: form));
  }

  /// Raw authenticated bytes (e.g. profile avatar images).
  Future<List<int>> getBytes(String path) async {
    try {
      final res = await _dio.get<List<int>>(path,
          options: Options(responseType: ResponseType.bytes));
      return res.data ?? const [];
    } on DioException catch (e) {
      throw _mapDio(e);
    }
  }

  Future<Map<String, dynamic>> _send(
      Future<Response<Map<String, dynamic>>> Function() run) async {
    try {
      final res = await run();
      return res.data ?? const {};
    } on DioException catch (e) {
      throw _mapDio(e);
    }
  }

  /// Maps any transport/HTTP failure to a professional, user-safe message.
  /// The server's own `error` sentence always wins; the status-based texts
  /// below are fallbacks for degraded/offline paths.
  ApiException _mapDio(DioException e) {
    return ApiException(_messageFor(e), statusCode: e.response?.statusCode);
  }

  String _messageFor(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final error = data['error'] ?? data['detail'];
      if (error is String && error.trim().isNotEmpty) {
        return error.trim();
      }
    }

    switch (e.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
        return 'Cannot reach EcoLoop right now. Please check your internet '
            'connection and try again.';
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'The connection timed out. Please try again.';
      case DioExceptionType.badResponse:
        break;
      case DioExceptionType.cancel:
        return 'The request was cancelled.';
      default:
        break;
    }

    switch (e.response?.statusCode) {
      case 400:
        return 'The request could not be completed. Please review the details '
            'and try again.';
      case 401:
        return 'Please log in to continue.';
      case 403:
        return 'You do not have permission to perform this action.';
      case 404:
        return 'This item could not be found.';
      case 409:
        return 'This already exists. Please review the details and try again.';
      case 413:
        return 'That image is too large. Please try again with a smaller photo.';
      case 422:
        return 'Some of the details you entered are invalid. Please review '
            'them and try again.';
      case 429:
        return 'Too many attempts. Please wait a moment and try again.';
      case int n when n >= 500:
        return 'Something went wrong on our side. Please try again shortly.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }
}