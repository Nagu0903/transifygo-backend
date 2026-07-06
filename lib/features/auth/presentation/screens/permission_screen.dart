import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/session_service.dart';
import 'role_selection_screen.dart';

class PermissionScreen extends StatefulWidget {
  const PermissionScreen({super.key});

  @override
  State<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends State<PermissionScreen> with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  bool _isRequesting = false;

  // List of permissions to display
  final List<PermissionItem> _permissions = [
    PermissionItem(
      icon: Icons.phone_outlined,
      title: 'Phone Permission',
      description: 'Required to call transporters and customers directly from the app.',
      isOptional: false,
      permission: Permission.phone,
    ),
    PermissionItem(
      icon: Icons.location_on_outlined,
      title: 'Location Permission',
      description: 'Used to find nearby loads, nearby vehicles, calculate distance, and improve load recommendations.',
      isOptional: false,
      permission: Permission.location,
    ),
    PermissionItem(
      icon: Icons.notifications_none_rounded,
      title: 'Notifications',
      description: 'Receive instant updates for new loads, bids, assignments, trip status, and payments.',
      isOptional: false,
      permission: Permission.notification,
    ),
    PermissionItem(
      icon: Icons.camera_alt_outlined,
      title: 'Camera',
      description: 'Used for uploading vehicle documents, POD images, profile photos, and trip proof.',
      isOptional: true,
      permission: Permission.camera,
    ),
    PermissionItem(
      icon: Icons.photo_library_outlined,
      title: 'Storage / Photos',
      description: 'Used to upload invoices, RC, DL, insurance, and load documents.',
      isOptional: true,
      permission: Permission.storage,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  void _handleDecline() {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'You must accept the Terms & Conditions to use TransifyGo.',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 4),
      ),
    );
  }

  Future<void> _handleAgreeAndContinue() async {
    if (_isRequesting) return;
    setState(() {
      _isRequesting = true;
    });

    try {
      // 1. Request notifications
      await Permission.notification.request();

      // 2. Request phone
      await Permission.phone.request();

      // 3. Request location
      await Permission.location.request();

      // 4. Request camera
      await Permission.camera.request();

      // 5. Request storage
      await Permission.storage.request();
      // Also request photos/media library for Android 13+ compatibility
      await Permission.photos.request();

      // Re-verify critical permissions (Phone & Location)
      final phoneStatus = await Permission.phone.status;
      final locationStatus = await Permission.location.status;

      if (phoneStatus.isDenied || locationStatus.isDenied) {
        if (mounted) {
          _showExplanationDialog(
            isPhoneDenied: phoneStatus.isDenied,
            isLocationDenied: locationStatus.isDenied,
          );
        }
      } else {
        await _completeOnboarding();
      }
    } catch (e) {
      debugPrint('[PermissionScreen] Error requesting permissions: $e');
      // Even in case of error, try to let the user proceed rather than getting stuck
      await _completeOnboarding();
    } finally {
      if (mounted) {
        setState(() {
          _isRequesting = false;
        });
      }
    }
  }

  Future<void> _completeOnboarding() async {
    await SessionService.setOnboardingCompleted();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const RoleSelectionScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
  }

  void _showExplanationDialog({required bool isPhoneDenied, required bool isLocationDenied}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.info_outline, color: AppColors.primaryBlue),
              const SizedBox(width: 10),
              Text(
                'Permissions Needed',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade800,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'To give you a seamless logistics experience, TransifyGo requires some permissions:',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),
              const SizedBox(height: 12),
              if (isPhoneDenied)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.phone_locked, size: 18, color: Colors.orange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Phone: Call transporters and customers directly from the app.',
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              if (isLocationDenied)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_off, size: 18, color: Colors.orange),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Location: Find nearby loads/vehicles and track active trips.',
                          style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                'Without these permissions, some features in the app may not function properly.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontStyle: FontStyle.italic),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await _completeOnboarding();
              },
              child: Text(
                'Continue Limited',
                style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: AppColors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                minimumSize: const Size(100, 36),
              ),
              onPressed: () async {
                Navigator.of(context).pop();
                await openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Scrollable permissions content
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 24),
                        // Logo & Brand Header
                        Center(
                          child: Column(
                            children: [
                              Container(
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
                              const SizedBox(height: 16),
                              const Text(
                                'Terms & Permissions',
                                style: TextStyle(
                                  color: Color(0xFF0D1B2A),
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                "India's Smart Transport Network",
                                style: TextStyle(
                                  color: Colors.grey.shade500,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                        const Text(
                          'Terms & App Permissions',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0D1B2A),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'TransifyGo only uses these permissions to provide secure, real-time logistics services and never shares your data without permission.',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade600,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 24),
                        
                        // Permissions Cards
                        ..._permissions.map((item) => _buildPermissionCard(item)),
                        
                        const SizedBox(height: 16),
                        
                        // Security Badge Explanation
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.green.shade100),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.security_rounded, color: Colors.green.shade700, size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Your privacy is our priority. All requested data is transmitted securely and handled in compliance with privacy guidelines.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.green.shade900,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            
            // Sticky Bottom Section (Actions & Links)
            Container(
              padding: const EdgeInsets.only(left: 24, right: 24, top: 16, bottom: 24),
              decoration: BoxDecoration(
                color: AppColors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Terms and Privacy links
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () => _launchURL('https://transifygo.com/privacy-policy'),
                        child: const Text(
                          'Privacy Policy',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.primaryBlue,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12.0),
                        child: Text(
                          '•',
                          style: TextStyle(color: Colors.grey.shade400),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _launchURL('https://transifygo.com/terms-and-conditions'),
                        child: const Text(
                          'Terms & Conditions',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.primaryBlue,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  
                  // Buttons (Decline & Agree)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isRequesting ? null : _handleDecline,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 54),
                            side: BorderSide(color: Colors.grey.shade300),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(
                            'Decline',
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: _isRequesting ? null : _handleAgreeAndContinue,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryBlue,
                            foregroundColor: AppColors.white,
                            minimumSize: const Size(double.infinity, 54),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            elevation: 0,
                          ),
                          child: _isRequesting
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                  ),
                                )
                              : const Text(
                                  'Agree & Continue',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.3,
                                  ),
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
    );
  }

  Widget _buildPermissionCard(PermissionItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon Box
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              item.icon,
              color: AppColors.primaryBlue,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          // Texts
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0D1B2A),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: item.isOptional ? Colors.grey.shade100 : AppColors.primaryBlue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.isOptional ? 'Optional' : 'Required',
                        style: TextStyle(
                          fontSize: 10,
                          color: item.isOptional ? Colors.grey.shade600 : AppColors.primaryBlue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  item.description,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade600,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class PermissionItem {
  final IconData icon;
  final String title;
  final String description;
  final bool isOptional;
  final Permission permission;

  PermissionItem({
    required this.icon,
    required this.title,
    required this.description,
    required this.isOptional,
    required this.permission,
  });
}
