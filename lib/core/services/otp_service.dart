import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:transify_app/core/network/api_service.dart';
import 'package:transify_app/firebase_options.dart';

/// Abstraction for OTP delivery and verification.
/// Allows swapping between Firebase, MSG91, Twilio, etc.
abstract class OtpProvider {
  Future<void> sendOtp({
    required String phone,
    required String role,
    required Function(String verificationId, int? resendToken) onCodeSent,
    required Function(String errorMessage) onFailed,
    Function(Map<String, dynamic> authResponse)? onVerificationCompleted,
    int? forceResendToken,
  });

  Future<Map<String, dynamic>> verifyOtp({
    required String verificationId,
    required String smsCode,
    required String role,
  });
}

/// Firebase Phone Authentication provider.
class FirebaseOtpProvider implements OtpProvider {
  final ApiService _apiService = ApiService();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String _redactPhone(String phone) {
    if (phone.length < 4) return '***';
    return '${phone.substring(0, phone.length - 4).replaceAll(RegExp(r'.'), '*')}${phone.substring(phone.length - 4)}';
  }

  @override
  Future<void> sendOtp({
    required String phone,
    required String role,
    required Function(String verificationId, int? resendToken) onCodeSent,
    required Function(String errorMessage) onFailed,
    Function(Map<String, dynamic> authResponse)? onVerificationCompleted,
    int? forceResendToken,
  }) async {
    // Format phone to E.164 (India prefix +91)
    final formattedPhone = phone.startsWith('+') ? phone : '+91$phone';
    debugPrint('[FirebaseOtpProvider] [LOG] Sending OTP request to Firebase for $formattedPhone');

    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: formattedPhone,
        timeout: const Duration(seconds: 45),
        forceResendingToken: forceResendToken,
        verificationCompleted: (PhoneAuthCredential credential) async {
          debugPrint('[FirebaseOtpProvider] [LOG] verificationCompleted callback: Auto-retrieved credentials.');
          try {
            final userCredential = await _auth.signInWithCredential(credential);
            final idToken = await userCredential.user!.getIdToken();
            if (idToken != null && idToken.isNotEmpty && onVerificationCompleted != null) {
              debugPrint('[FirebaseOtpProvider] [SUCCESS] Firebase ID token obtained via auto-verification.');
              final response = await _apiService.post('/auth/firebase-login', {
                'role': role,
                'idToken': idToken,
              });
              if (response.data['success'] == true) {
                onVerificationCompleted(response.data);
              } else {
                onFailed(response.data['message'] ?? 'Auto-verification login failed');
              }
            }
          } catch (e) {
            debugPrint('[FirebaseOtpProvider] [ERROR] Auto-verification login exception: $e');
            onFailed(e.toString());
          }
        },
        verificationFailed: (FirebaseAuthException e) {
          final buildMode = kReleaseMode ? 'release' : 'debug';
          final redactedPhone = _redactPhone(phone);
          final projectId = DefaultFirebaseOptions.android.projectId;
          const packageId = 'com.transify.app';

          debugPrint('[FIREBASE_AUTH_FAILED] code="${e.code}"');
          debugPrint('[FIREBASE_AUTH_FAILED] message="${e.message}"');
          debugPrint('[FIREBASE_AUTH_FAILED] phone="$redactedPhone"');
          debugPrint('[FIREBASE_AUTH_FAILED] projectId="$projectId"');
          debugPrint('[FIREBASE_AUTH_FAILED] packageId="$packageId"');
          debugPrint('[FIREBASE_AUTH_FAILED] buildMode="$buildMode"');

          String friendlyError = 'Failed to verify phone number. Please try again.';
          if (e.code == 'billing-not-enabled' || 
              (e.message != null && e.message!.toUpperCase().contains('BILLING_NOT_ENABLED'))) {
            friendlyError = 'OTP service is temporarily unavailable. Please contact support.';
          } else if (e.code == 'invalid-phone-number') {
            friendlyError = 'The phone number entered is invalid.';
          } else if (e.code == 'quota-exceeded') {
            friendlyError = 'SMS quota exceeded. Please try again later.';
          } else if (e.message != null) {
            friendlyError = e.message!;
          }
          onFailed(friendlyError);
        },
        codeSent: (String verificationId, int? resendToken) {
          debugPrint('[FirebaseOtpProvider] [SUCCESS] codeSent callback: verificationId=$verificationId');
          onCodeSent(verificationId, resendToken);
        },
        codeAutoRetrievalTimeout: (String verificationId) {
          debugPrint('[FirebaseOtpProvider] [LOG] codeAutoRetrievalTimeout callback: verificationId=$verificationId');
        },
      );
    } catch (e) {
      debugPrint('[FirebaseOtpProvider] [ERROR] verifyPhoneNumber exception: $e');
      onFailed(e.toString());
    }
  }

  @override
  Future<Map<String, dynamic>> verifyOtp({
    required String verificationId,
    required String smsCode,
    required String role,
  }) async {
    debugPrint('[FirebaseOtpProvider] [LOG] Verifying OTP: $smsCode for verificationId: $verificationId, role: $role');
    try {
      // 1. Sign in to Firebase Auth
      final credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      final userCredential = await _auth.signInWithCredential(credential);

      // 2. Retrieve Firebase ID Token
      final idToken = await userCredential.user!.getIdToken();
      if (idToken == null || idToken.isEmpty) {
        throw 'Failed to retrieve security token from Firebase.';
      }
      debugPrint('[FirebaseOtpProvider] [SUCCESS] Firebase auth token obtained.');

      // 3. Verify against Node.js Backend & get application JWT session
      final response = await _apiService.post('/auth/firebase-login', {
        'role': role,
        'idToken': idToken,
      });

      if (response.data['success'] == true) {
        return response.data;
      }
      throw response.data['message'] ?? 'Authentication failed';
    } catch (e) {
      debugPrint('[FirebaseOtpProvider] [ERROR] Exception during verify-otp: $e');
      rethrow;
    }
  }
}

/// Node.js Backend implementation of OtpProvider utilizing MSG91 SMS gateway (Legacy fallback).
class BackendOtpProvider implements OtpProvider {
  final ApiService _apiService = ApiService();

  @override
  Future<void> sendOtp({
    required String phone,
    required String role,
    required Function(String verificationId, int? resendToken) onCodeSent,
    required Function(String errorMessage) onFailed,
    Function(Map<String, dynamic> authResponse)? onVerificationCompleted,
    int? forceResendToken,
  }) async {
    debugPrint('[BackendOtpProvider] [LOG] Sending OTP request to backend for $phone');
    try {
      final response = await _apiService.post('/auth/send-otp', {
        'phone': phone,
      });

      if (response.data['success']) {
        debugPrint('[BackendOtpProvider] [SUCCESS] OTP sent to $phone');
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
    _instance ??= FirebaseOtpProvider(); // Defaulting to Firebase Phone Auth
    return _instance!;
  }

  @visibleForTesting
  static void setProvider(OtpProvider provider) {
    _instance = provider;
  }
}
