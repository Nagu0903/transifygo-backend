import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:transify_app/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:transify_app/core/constants/app_colors.dart';
import 'package:transify_app/core/localization/language_provider.dart';
import 'tabs/find_loads_tab.dart';
import 'tabs/accepted_loads_tab.dart';

class FindLoadsScreen extends StatefulWidget {
  const FindLoadsScreen({super.key});

  @override
  State<FindLoadsScreen> createState() => _FindLoadsScreenState();
}

class _FindLoadsScreenState extends State<FindLoadsScreen> {
  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(lang.translate('app_name')),
          actions: [
            IconButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen())), 
              icon: const Icon(Icons.notifications_active_outlined, color: AppColors.primaryBlue)
            ),
          ],
          bottom: TabBar(
            indicatorColor: AppColors.primaryBlue,
            labelColor: AppColors.primaryBlue,
            unselectedLabelColor: Colors.grey,
            tabs: [
              Tab(text: lang.translate('find_loads')),
              Tab(text: lang.translate('accepted')),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            FindLoadsTab(),
            AcceptedLoadsTab(),
          ],
        ),
      ),
    );
  }
}
