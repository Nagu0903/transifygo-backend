import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:transify_app/core/constants/app_colors.dart';
import 'package:transify_app/core/localization/language_provider.dart';
import 'tabs/owner_home_tab.dart';
import 'tabs/post_load_tab.dart';
import 'tabs/my_loads_tab.dart';
import 'tabs/owner_profile_tab.dart';

class OwnerDashboardScreen extends StatefulWidget {
  const OwnerDashboardScreen({super.key});

  @override
  State<OwnerDashboardScreen> createState() => _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends State<OwnerDashboardScreen> {
  int _currentIndex = 0;

  final List<Widget> _tabs = [
    const OwnerHomeTab(),
    const PostLoadTab(),
    const MyLoadsTab(),
    const OwnerProfileTab(),
  ];

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);

    return Scaffold(
      body: _tabs[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.primaryBlue,
        unselectedItemColor: Colors.grey,
        items: [
          BottomNavigationBarItem(icon: const Icon(Icons.home_outlined), activeIcon: const Icon(Icons.home), label: lang.translate('home')),
          BottomNavigationBarItem(icon: const Icon(Icons.add_box_outlined), activeIcon: const Icon(Icons.add_box), label: lang.translate('post_load')),
          BottomNavigationBarItem(icon: const Icon(Icons.local_shipping_outlined), activeIcon: const Icon(Icons.local_shipping), label: lang.translate('my_loads')),
          BottomNavigationBarItem(icon: const Icon(Icons.person_outline), activeIcon: const Icon(Icons.person), label: lang.translate('profile')),
        ],
      ),
    );
  }
}
