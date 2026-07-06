import 'package:dio/dio.dart';
import 'dart:developer' as dev;
import 'package:transify_app/core/services/session_service.dart';

class ApiService {
  // Actual Render Backend URL
  static const String baseUrl = 'https://transifygo-backend.onrender.com/api';
  
  static final ApiService _instance = ApiService._internal();

  factory ApiService() {
    return _instance;
  }
  
  final Dio _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
  ));

  ApiService._internal() {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        // Normalize base URL and path to prevent Dio path-absolute resolution stripping the /api/ segment
        if (!options.baseUrl.endsWith('/')) {
          options.baseUrl = '${options.baseUrl}/';
        }
        if (options.path.startsWith('/')) {
          options.path = options.path.substring(1);
        }

        try {
          final session = await SessionService.getSession();
          final token = session['token'];
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
        } catch (e) {
          dev.log('Error setting Authorization header: $e');
        }

        final fullUrl = '${options.baseUrl}${options.path}';
        dev.log('API Request URL: $fullUrl');
        dev.log('HTTP Method: ${options.method}');
        dev.log('Headers: ${options.headers}');
        dev.log('Request Body: ${options.data}');
        return handler.next(options);
      },
      onResponse: (response, handler) {
        dev.log('API Response: ${response.statusCode} ${response.data}');
        return handler.next(response);
      },
      onError: (DioException e, handler) {
        dev.log('API Error: ${e.message}');
        if (e.response != null) {
          dev.log('Error Data: ${e.response?.data}');
        }
        return handler.next(e);
      },
    ));
  }

  String _handleDioException(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout) {
      return 'Connection timed out. Ensure the backend is running and your IP is correct.';
    }
    if (e.type == DioExceptionType.receiveTimeout) {
      return 'Database response timeout. MongoDB might be busy, please try again.';
    }

    // Check for host lookup or socket exceptions (Render unavailable or offline)
    final errorMsg = e.message ?? '';
    final innerErrorMsg = e.error?.toString() ?? '';
    if (e.type == DioExceptionType.connectionError ||
        errorMsg.contains('Failed host lookup') ||
        errorMsg.contains('SocketException') ||
        innerErrorMsg.contains('SocketException') ||
        innerErrorMsg.contains('Failed host lookup')) {
      return 'Server is temporarily unavailable. Please try again.';
    }

    if (e.response != null && e.response?.data is Map) {
      return e.response?.data['message'] ?? 'Server error occurred';
    }
    return e.message ?? 'Network error occurred';
  }

  Future<Response> post(String path, dynamic data, {bool isPut = false}) async {
    try {
      if (isPut) {
        return await _dio.put(path, data: data);
      }
      return await _dio.post(path, data: data);
    } on DioException catch (e) {
      throw _handleDioException(e);
    } catch (e) {
      throw e.toString();
    }
  }

  Future<Response> get(String path) async {
    try {
      return await _dio.get(path);
    } on DioException catch (e) {
      throw _handleDioException(e);
    } catch (e) {
      throw e.toString();
    }
  }

  Future<Response> put(String path, dynamic data) async {
    return post(path, data, isPut: true);
  }

  Future<Response> delete(String path) async {
    try {
      return await _dio.delete(path);
    } on DioException catch (e) {
      throw _handleDioException(e);
    } catch (e) {
      throw e.toString();
    }
  }
}
