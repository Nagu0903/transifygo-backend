import 'package:flutter/material.dart';
import 'package:transify_app/core/constants/app_colors.dart';
import 'package:transify_app/core/services/session_service.dart';
import 'package:transify_app/features/auth/presentation/screens/role_selection_screen.dart';
import 'package:transify_app/features/load_owner/presentation/screens/owner_dashboard_screen.dart';
import 'package:transify_app/features/driver/presentation/screens/driver_dashboard_screen.dart';
import 'package:transify_app/features/admin/presentation/screens/admin_dashboard_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.6, curve: Curves.easeIn)),
    );

    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack)),
    );

    _controller.forward();
    _checkSession();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _checkSession() async {
    // Artificial delay for splash experience (3 seconds total)
    await Future.delayed(const Duration(seconds: 3));
    if (!mounted) return;

    final isLoggedIn = await SessionService.isLoggedIn();
    if (!mounted) return;
    
    if (isLoggedIn) {
      final session = await SessionService.getSession();
      if (!mounted) return;
      
      final role = session['role'];

      if (role == 'Load Owner') {
        _navigate(const OwnerDashboardScreen());
      } else if (role == 'Driver') {
        _navigate(const DriverDashboardScreen());
      } else if (role == 'Admin') {
        _navigate(const AdminDashboardScreen());
      } else {
        _navigate(const RoleSelectionScreen());
      }
    } else {
      _navigate(const RoleSelectionScreen());
    }
  }

  void _navigate(Widget screen) {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => screen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 800),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF0D1B2A), // Very Dark Blue
              Color(0xFF1B263B), // Dark Blue
              Colors.black,
            ],
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Opacity(
                  opacity: _fadeAnimation.value,
                  child: Transform.scale(
                    scale: _scaleAnimation.value,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Animated Logo Glow Effect
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primaryOrange.withValues(alpha: 0.2),
                                blurRadius: 40,
                                spreadRadius: 10,
                              ),
                            ],
                          ),
                          child: Image.asset(
                            'assets/logo/logo.png',
                            width: 180,
                            height: 180,
                          ),
                        ),
                        const SizedBox(height: 30),
                        // App Name
                        const Text(
                          'TRANSIFY',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        // Tagline
                        Text(
                          'SMART LOAD BOOKING NETWORK',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 60),
                        // Professional Loader
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppColors.primaryOrange.withValues(alpha: 0.8),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            // App Version at Bottom
            Position64(
              bottom: 40,
              child: Text(
                'v1.0.0',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 12,
                  letterSpacing: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Simple Helper to handle Positioned better in this context
class Position64 extends StatelessWidget {
  final double? bottom;
  final Widget child;
  const Position64({super.key, this.bottom, required this.child});
  @override
  Widget build(BuildContext context) => Positioned(bottom: bottom, child: child);
}
