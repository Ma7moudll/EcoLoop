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

  Future<Map<String, dynamic>> postMultipart(
    String path,
    List<int> imageBytes, {
    String field = 'image',
    String filename = 'capture.jpg',
  }) async {
    final form = FormData.fromMap({
      field: MultipartFile.fromBytes(
        imageBytes,
        filename: filename,
        contentType: DioMediaType('image', 'jpeg'),
      ),
    });
    return _send(() => _dio.post<Map<String, dynamic>>(path, data: form));
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

  ApiException _mapDio(DioException e) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    if (data is Map) {
      final error = data['error'];
      if (error is String && error.isNotEmpty) {
        return ApiException(error, statusCode: status);
      }
    }
    if (e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout) {
      return const ApiException(
        'Cannot reach the Recycle Vision service. Is the backend running?',
      );
    }
    return ApiException(
      status == null ? 'Request failed.' : 'Request failed ($status).',
      statusCode: status,
    );
  }
}