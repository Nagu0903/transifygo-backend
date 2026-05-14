import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:transify_app/core/constants/app_colors.dart';
import 'package:transify_app/core/localization/language_provider.dart';
import 'find_loads_screen.dart';
import 'driver_profile_screen.dart';

class DriverDashboardScreen extends StatefulWidget {
  const DriverDashboardScreen({super.key});

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const FindLoadsScreen(),
    const DriverProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);

    return Scaffold(
      body: _screens[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        selectedItemColor: AppColors.primaryBlue,
        items: [
          BottomNavigationBarItem(icon: const Icon(Icons.search), label: lang.translate('find_loads')),
          BottomNavigationBarItem(icon: const Icon(Icons.person), label: lang.translate('profile')),
        ],
      ),
    );
  }
}
