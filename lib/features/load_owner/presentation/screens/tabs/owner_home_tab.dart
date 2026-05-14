import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:transify_app/core/constants/app_colors.dart';
import 'package:transify_app/core/localization/language_provider.dart';
import 'package:transify_app/core/services/session_service.dart';
import 'package:transify_app/features/load_owner/presentation/bloc/load_bloc.dart';

class OwnerHomeTab extends StatefulWidget {
  const OwnerHomeTab({super.key});

  @override
  State<OwnerHomeTab> createState() => _OwnerHomeTabState();
}

class _OwnerHomeTabState extends State<OwnerHomeTab> {
  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    final session = await SessionService.getSession();
    final uid = session['uid'];
    if (uid != null && mounted) {
      context.read<LoadBloc>().add(FetchOwnerLoadsRequested(uid));
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(lang.translate('app_name'), style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none)),
        ],
      ),
      body: FutureBuilder<Map<String, String?>>(
        future: SessionService.getSession(),
        builder: (context, sessionSnap) {
          if (!sessionSnap.hasData) return const Center(child: CircularProgressIndicator());
          final name = sessionSnap.data!['name'] ?? 'User';

          return BlocBuilder<LoadBloc, LoadState>(
            builder: (context, state) {
              int total = 0, active = 0, accepted = 0, completed = 0;
              List<Map<String, dynamic>> loads = [];

              if (state is LoadLoading) return const Center(child: CircularProgressIndicator());

              if (state is LoadSuccess && state.loads != null) {
                loads = state.loads!;
                total = loads.length;
                for (var data in loads) {
                  final status = (data['status'] ?? '').toString().toLowerCase();
                  if (status == 'pending') active++;
                  if (status == 'accepted') accepted++;
                  if (status == 'completed') completed++;
                }
              }

              return RefreshIndicator(
                onRefresh: _fetchData,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildWelcomeCard(name),
                      const SizedBox(height: 24),
                      Text(
                        lang.translate('load_statistics'),
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 16),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 16,
                        mainAxisSpacing: 16,
                        childAspectRatio: 1.5,
                        children: [
                          _buildStatCard('Total Loads', total.toString(), Colors.blue),
                          _buildStatCard('Active Loads', active.toString(), Colors.orange),
                          _buildStatCard('Accepted', accepted.toString(), Colors.green),
                          _buildStatCard('Completed', completed.toString(), Colors.purple),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _buildRecentActivity(lang, loads),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildWelcomeCard(String name) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: AppColors.primaryBlue.withValues(alpha: 0.3), blurRadius: 15, offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Welcome back,', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 16)),
          const SizedBox(height: 4),
          Text(name, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(12)),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Verified Owner', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, Color color) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(title, style: const TextStyle(fontSize: 14, color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentActivity(LanguageProvider lang, List<Map<String, dynamic>> loads) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Recent Loads', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            TextButton(onPressed: () {}, child: const Text('View All')),
          ],
        ),
        if (loads.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: Text('No loads posted yet', style: TextStyle(color: Colors.grey))),
          )
        else
          ...loads.take(3).map((data) => Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: const CircleAvatar(backgroundColor: Colors.orange, child: Icon(Icons.local_shipping, color: Colors.white)),
              title: Text('${data['fromLocation']} → ${data['toLocation']}'),
              subtitle: Text('${data['material']} • ${data['weight'] ?? 'N/A'}'),
              trailing: Text(
                (data['status'] ?? 'pending').toString().toUpperCase(), 
                style: TextStyle(
                  color: (data['status'] ?? '').toString().toLowerCase() == 'pending' 
                    ? Colors.orange 
                    : ((data['status'] ?? '').toString().toLowerCase() == 'accepted' ? Colors.green : Colors.purple),
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                )
              ),
            ),
          )),
      ],
    );
  }
}
