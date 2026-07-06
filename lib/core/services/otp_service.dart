import 'package:flutter/foundation.dart';
import 'package:transify_app/core/network/api_service.dart';

/// Abstraction for OTP delivery and verification.
/// Allows swapping between Firebase, MSG91, Twilio, etc.
abstract class OtpProvider {
  Future<void> sendOtp({
    required String phone,
    required Function(String verificationId, int? resendToken) onCodeSent,
    required Function(String errorMessage) onFailed,
    int? forceResendToken,
  });

  Future<Map<String, dynamic>> verifyOtp({
    required String verificationId,
    required String smsCode,
    required String role,
  });
}

/// Node.js Backend implementation of OtpProvider utilizing MSG91 SMS gateway.
class BackendOtpProvider implements OtpProvider {
  final ApiService _apiService = ApiService();

  @override
  Future<void> sendOtp({
    required String phone,
    required Function(String verificationId, int? resendToken) onCodeSent,
    required Function(String errorMessage) onFailed,
    int? forceResendToken,
  }) async {
    debugPrint('[BackendOtpProvider] [LOG] Sending OTP request to backend for $phone');
    try {
      final response = await _apiService.post('/auth/send-otp', {
        'phone': phone,
      });

      if (response.data['success']) {
        debugPrint('[BackendOtpProvider] [SUCCESS] OTP sent to $phone');
        // The phone number acts as the verificationId since the backend associates OTP by phone
        onCodeSent(phone, null);
      } else {
        final errMsg = response.data['message'] ?? 'Failed to send OTP';
        debugPrint('[BackendOtpProvider] [FAILED] Backend returned success=false: $errMsg');
        onFailed(errMsg);
      }
    } catch (e) {
      debugPrint('[BackendOtpProvider] [ERROR] Exception during send-otp: $e');
      onFailed(e.toString());
    }
  }

  @override
  Future<Map<String, dynamic>> verifyOtp({
    required String verificationId,
    required String smsCode,
    required String role,
  }) async {
    debugPrint('[BackendOtpProvider] [LOG] Verifying OTP: $smsCode for phone: $verificationId, role: $role');
    try {
      final response = await _apiService.post('/auth/verify-otp', {
        'phone': verificationId,
        'otp': smsCode,
        'role': role,
      });

      if (response.data['success'] == true) {
        return response.data;
      }
      throw response.data['message'] ?? 'Invalid OTP verification response';
    } catch (e) {
      debugPrint('[BackendOtpProvider] [ERROR] Exception during verify-otp: $e');
      rethrow;
    }
  }
}

/// Factory service to select the active OTP provider.
class OtpService {
  static OtpProvider? _instance;

  static OtpProvider get provider {
    _instance ??= BackendOtpProvider();
    return _instance!;
  }

  @visibleForTesting
  static void setProvider(OtpProvider provider) {
    _instance = provider;
  }
}
