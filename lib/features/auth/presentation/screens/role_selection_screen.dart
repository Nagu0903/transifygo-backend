import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:transify_app/core/constants/app_colors.dart';
import 'package:transify_app/core/localization/language_provider.dart';
import 'package:transify_app/features/auth/presentation/screens/login_screen.dart';


class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.primaryBlue, AppColors.secondaryBlue],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 40),
              Image.asset('assets/logo/logo.png', height: 120),
              const SizedBox(height: 20),
              Text(
                lang.translate('role_selection'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    _buildRoleCard(
                      context,
                      title: lang.translate('load_owner'),
                      icon: Icons.business_center,
                      onTap: () => _navigateToLogin(context, 'Load Owner'),
                    ),
                    const SizedBox(height: 16),
                    _buildRoleCard(
                      context,
                      title: lang.translate('driver'),
                      icon: Icons.local_shipping,
                      onTap: () => _navigateToLogin(context, 'Driver'),
                    ),
                    const SizedBox(height: 16),
                    _buildRoleCard(
                      context,
                      title: lang.translate('admin'),
                      icon: Icons.admin_panel_settings,
                      onTap: () => _navigateToLogin(context, 'Admin'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
              TextButton(
                onPressed: () {
                  final newLang = lang.currentLocale.languageCode == 'en' ? 'kn' : 'en';
                  lang.changeLanguage(newLang);
                },
                child: Text(
                  lang.currentLocale.languageCode == 'en' ? 'ಕನ್ನಡದಲ್ಲಿ ಓದಿ' : 'Read in English',
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleCard(BuildContext context, {required String title, required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primaryOrange.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.primaryOrange, size: 30),
            ),
            const SizedBox(width: 20),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.primaryBlue,
              ),
            ),
            const Spacer(),
            const Icon(Icons.arrow_forward_ios, color: Colors.grey, size: 16),
          ],
        ),
      ),
    );
  }

  void _navigateToLogin(BuildContext context, String role) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LoginScreen(role: role),
      ),
    );
  }
}
