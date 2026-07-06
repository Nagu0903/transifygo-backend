import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:transify_app/core/constants/app_colors.dart';
import 'package:transify_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:transify_app/features/auth/domain/models/user_model.dart';
import 'package:transify_app/features/load_owner/presentation/screens/owner_dashboard_screen.dart';
import 'package:transify_app/features/driver/presentation/screens/driver_dashboard_screen.dart';
import 'package:transify_app/features/admin/presentation/screens/admin_dashboard_screen.dart';
import 'package:transify_app/core/utils/snackbar_utils.dart';
import 'package:transify_app/core/services/otp_service.dart';

class LoginScreen extends StatefulWidget {
  final String role;
  const LoginScreen({super.key, required this.role});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  final _phoneController = TextEditingController();
  final List<TextEditingController> _otpControllers = List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());
  
  int _step = 1; // 1: Phone input, 2: OTP input
  bool _isLoading = false;
  String? _verificationId;
  int? _resendToken;
  
  Timer? _timer;
  Timer? _uiTimeoutTimer;
  int _secondsRemaining = 30;
  bool _canResend = false;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _uiTimeoutTimer?.cancel();
    _phoneController.dispose();
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var node in _otpFocusNodes) {
      node.dispose();
    }
    _fadeController.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    setState(() {
      _secondsRemaining = 30;
      _canResend = false;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        setState(() {
          _secondsRemaining--;
        });
      } else {
        setState(() {
          _canResend = true;
          _timer?.cancel();
        });
      }
    });
  }

  Future<void> _sendOTP() async {
    final phone = _phoneController.text.trim();
    if (phone.length != 10) {
      SnackBarUtils.showWarning(context, 'Please enter a valid 10-digit mobile number');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    _uiTimeoutTimer?.cancel();
    _uiTimeoutTimer = Timer(const Duration(seconds: 45), () {
      if (mounted && _isLoading) {
        setState(() {
          _isLoading = false;
        });
        SnackBarUtils.showError(context, 'Verification request timed out. Please check your network and try again.');
      }
    });

    try {
      await OtpService.provider.sendOtp(
        phone: phone,
        forceResendToken: _resendToken,
        onCodeSent: (String verificationId, int? resendToken) {
          _uiTimeoutTimer?.cancel();
          setState(() {
            _verificationId = verificationId;
            _resendToken = resendToken;
            _isLoading = false;
            _step = 2; // Move to OTP input
          });
          _fadeController.reset();
          _fadeController.forward();
          _startResendTimer();
        },
        onFailed: (String errorMessage) {
          _uiTimeoutTimer?.cancel();
          setState(() {
            _isLoading = false;
          });
          if (mounted) {
            SnackBarUtils.showError(context, errorMessage);
          }
        },
      );
    } catch (e) {
      _uiTimeoutTimer?.cancel();
      setState(() {
        _isLoading = false;
      });
      if (mounted) SnackBarUtils.showError(context, 'Failed to send OTP: $e');
    }
  }

  Future<void> _verifyOTP() async {
    String smsCode = _otpControllers.map((c) => c.text.trim()).join();
    if (smsCode.length != 6) {
      SnackBarUtils.showWarning(context, 'Please enter the 6-digit OTP');
      return;
    }

    if (_verificationId == null) {
      SnackBarUtils.showError(context, 'Verification ID is missing. Please request OTP again.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await OtpService.provider.verifyOtp(
        verificationId: _verificationId!,
        smsCode: smsCode,
        role: widget.role,
      );

      final token = response['token'];
      final userMap = response['user'];
      final userModel = UserModel.fromMap(userMap, userMap['id'] ?? userMap['_id']);

      if (mounted) {
        context.read<AuthBloc>().add(OtpLoginSucceeded(token: token, user: userModel));
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) SnackBarUtils.showError(context, e.toString());
    }
  }

  Future<void> _launchURL(String urlString) async {
    final uri = Uri.parse(urlString);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open page: $urlString')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening link: $e')),
        );
      }
    }
  }

  void _navigateToDashboard(BuildContext context, String role) {
    Widget dashboard;
    switch (role) {
      case 'Load Owner':
        dashboard = const OwnerDashboardScreen();
        break;
      case 'Driver':
        dashboard = const DriverDashboardScreen();
        break;
      case 'Admin':
        dashboard = const AdminDashboardScreen();
        break;
      default:
        return;
    }
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => dashboard), (route) => false);
  }

  @override
  Widget build(BuildContext context) {

    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthAuthenticated) {
          _navigateToDashboard(context, state.role);
        } else if (state is AuthError) {
          SnackBarUtils.showError(context, state.message);
          setState(() {
            _isLoading = false;
          });
        }
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              // Header Back Button
              Padding(
                padding: const EdgeInsets.only(left: 16.0, top: 16.0),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF0D1B2A), size: 22),
                    onPressed: () {
                      if (_step == 2) {
                        setState(() {
                          _step = 1;
                        });
                        _fadeController.reset();
                        _fadeController.forward();
                      } else {
                        Navigator.pop(context);
                      }
                    },
                  ),
                ),
              ),
              
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28.0),
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 16),
                          // TransifyGo Logo
                          Center(
                            child: Hero(
                              tag: 'logo',
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.primaryBlue.withValues(alpha: 0.05),
                                ),
                                child: Image.asset(
                                  'assets/logo/logo.png',
                                  width: 80,
                                  height: 80,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),

                          if (_step == 1) ...[
                            // STEP 1: Phone input screen
                            const Text(
                              'Get Started',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0D1B2A),
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Enter your phone number to sign in or register automatically.',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade500,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 36),

                            // Phone Number Field
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              child: Row(
                                children: [
                                  // Country Code Prefix
                                  Text(
                                    '+91',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade800,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Container(
                                    width: 1,
                                    height: 24,
                                    color: Colors.grey.shade300,
                                  ),
                                  const SizedBox(width: 16),
                                  // Field
                                  Expanded(
                                    child: TextField(
                                      controller: _phoneController,
                                      keyboardType: TextInputType.phone,
                                      maxLength: 10,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.0,
                                      ),
                                      decoration: const InputDecoration(
                                        hintText: 'Enter Phone Number',
                                        hintStyle: TextStyle(
                                          fontWeight: FontWeight.normal,
                                          letterSpacing: 0,
                                          color: Colors.grey,
                                        ),
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        counterText: '',
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 32),

                            // Continue Button
                            ElevatedButton(
                              onPressed: _isLoading ? null : _sendOTP,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryBlue,
                                foregroundColor: AppColors.white,
                                minimumSize: const Size(double.infinity, 56),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 0,
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    )
                                  : const Text(
                                      'Continue',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ] else ...[
                            // STEP 2: OTP verification screen
                            const Text(
                              'Verify Phone',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0D1B2A),
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'We sent a 6-digit OTP code to +91 ${_phoneController.text.trim()}',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade500,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 36),

                            // 6-digit OTP Fields
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: List.generate(6, (index) {
                                return SizedBox(
                                  width: 44,
                                  child: TextField(
                                    controller: _otpControllers[index],
                                    focusNode: _otpFocusNodes[index],
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    maxLength: 1,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primaryBlue,
                                    ),
                                    decoration: InputDecoration(
                                      counterText: '',
                                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: Colors.grey.shade300),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(color: Colors.grey.shade300),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: const BorderSide(color: AppColors.primaryBlue, width: 2),
                                      ),
                                    ),
                                    onChanged: (value) {
                                      if (value.isNotEmpty) {
                                        if (index < 5) {
                                          _otpFocusNodes[index + 1].requestFocus();
                                        } else {
                                          _otpFocusNodes[index].unfocus();
                                          _verifyOTP(); // Auto-verify on final digit
                                        }
                                      } else {
                                        if (index > 0) {
                                          _otpFocusNodes[index - 1].requestFocus();
                                        }
                                      }
                                    },
                                  ),
                                );
                              }),
                            ),
                            const SizedBox(height: 32),

                            // Resend Timer & Button
                            Center(
                              child: TextButton(
                                onPressed: _canResend ? _sendOTP : null,
                                child: Text(
                                  _canResend ? 'Resend OTP' : 'Resend OTP in ${_secondsRemaining}s',
                                  style: TextStyle(
                                    color: _canResend ? AppColors.primaryBlue : Colors.grey.shade500,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Verify Button
                            ElevatedButton(
                              onPressed: _isLoading ? null : _verifyOTP,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primaryBlue,
                                foregroundColor: AppColors.white,
                                minimumSize: const Size(double.infinity, 56),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                elevation: 0,
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.5,
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                      ),
                                    )
                                  : const Text(
                                      'Verify OTP',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ],
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Legal Policy Links
              Padding(
                padding: const EdgeInsets.only(bottom: 24.0, left: 24, right: 24),
                child: Column(
                  children: [
                    Text(
                      'By continuing, you agree to our',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: () => _launchURL('https://transifygo.com/terms-and-conditions'),
                          child: const Text(
                            'Terms & Conditions',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.primaryBlue,
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8.0),
                          child: Text(
                            'and',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => _launchURL('https://transifygo.com/privacy-policy'),
                          child: const Text(
                            'Privacy Policy',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.primaryBlue,
                              fontWeight: FontWeight.bold,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
