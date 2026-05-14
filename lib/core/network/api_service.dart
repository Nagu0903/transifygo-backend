import 'package:dio/dio.dart';
import 'dart:developer' as dev;

class ApiService {
  // Final Production Render Backend URL
  static const String baseUrl = 'https://transify-backend.onrender.com/api';
  
  final Dio _dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
  ));

  ApiService() {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        dev.log('API Request: ${options.method} ${options.path}');
        dev.log('Data: ${options.data}');
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

  Future<Response> post(String path, dynamic data, {bool isPut = false}) async {
    try {
      if (isPut) {
        return await _dio.put(path, data: data);
      }
      return await _dio.post(path, data: data);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout) {
        throw 'Connection timed out. Ensure the backend is running and your IP is correct.';
      }
      if (e.type == DioExceptionType.receiveTimeout) {
        throw 'Database response timeout. MongoDB might be busy, please try again.';
      }
      if (e.response != null && e.response?.data is Map) {
        throw e.response?.data['message'] ?? 'Server error occurred';
      }
      throw e.message ?? 'Network error occurred';
    } catch (e) {
      throw e.toString();
    }
  }

  Future<Response> get(String path) async {
    try {
      return await _dio.get(path);
    } on DioException catch (e) {
      if (e.response != null && e.response?.data is Map) {
        throw e.response?.data['message'] ?? 'Server error occurred';
      }
      throw e.message ?? 'Network error occurred';
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
      if (e.response != null && e.response?.data is Map) {
        throw e.response?.data['message'] ?? 'Server error occurred';
      }
      throw e.message ?? 'Network error occurred';
    } catch (e) {
      throw e.toString();
    }
  }
}
