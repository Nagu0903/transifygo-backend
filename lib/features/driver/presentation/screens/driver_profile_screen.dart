import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:transify_app/core/constants/app_colors.dart';
import 'package:transify_app/core/localization/language_provider.dart';
import 'package:transify_app/core/services/session_service.dart';
import 'package:transify_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:transify_app/features/auth/presentation/screens/role_selection_screen.dart';


class DriverProfileScreen extends StatelessWidget {
  const DriverProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);

    return Scaffold(
      appBar: AppBar(title: Text(lang.translate('profile'))),
      body: FutureBuilder<Map<String, String?>>(
        future: SessionService.getSession(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const CircleAvatar(
                  radius: 50,
                  backgroundColor: AppColors.primaryBlue,
                  child: Icon(Icons.drive_eta, size: 60, color: Colors.white),
                ),
                const SizedBox(height: 16),
                Text(data['name'] ?? 'Driver', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                Text(data['phone'] ?? '', style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 32),
                _buildSection(context, lang, 'Support', [
                  _buildProfileItem(icon: Icons.phone, title: 'Call Support', onTap: () => launchUrl(Uri.parse('tel:6363788419'))),
                  _buildProfileItem(icon: FontAwesomeIcons.whatsapp, title: 'WhatsApp', onTap: () => launchUrl(Uri.parse('https://wa.me/916363788419'))),
                  _buildProfileItem(
                    icon: Icons.language,
                    title: lang.currentLocale.languageCode == 'en' ? 'Switch to Kannada' : 'Switch to English',
                    onTap: () {
                      final newLang = lang.currentLocale.languageCode == 'en' ? 'kn' : 'en';
                      lang.changeLanguage(newLang);
                    },
                  ),
                ]),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  onPressed: () => _showLogoutDialog(context),
                  icon: const Icon(Icons.logout),
                  label: Text(lang.translate('logout')),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade400),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSection(BuildContext context, LanguageProvider lang, String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildProfileItem({required IconData icon, required String title, required VoidCallback onTap}) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primaryBlue),
      title: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
      trailing: const Icon(Icons.chevron_right, size: 20),
      onTap: onTap,
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              context.read<AuthBloc>().add(LogoutRequested());
              Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const RoleSelectionScreen()), (route) => false);
            },
            child: const Text('Logout', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
