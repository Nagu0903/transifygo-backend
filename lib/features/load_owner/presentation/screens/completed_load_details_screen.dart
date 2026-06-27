import 'package:flutter/material.dart';
import 'package:transify_app/core/constants/app_colors.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/payment_management_section.dart';

class CompletedLoadDetailsScreen extends StatelessWidget {
  final Map<String, dynamic> loadData;

  const CompletedLoadDetailsScreen({super.key, required this.loadData});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('Load Delivery Proof'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Load Info Card
            _buildInfoCard(),
            
            // Payment Management Section
            PaymentManagementSection(loadData: loadData),
            const SizedBox(height: 20),
            
            // Proof Photos Section
            const Text(
              'Proof of Delivery',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildProofSection(context, 'Delivery Photo', loadData['deliveryPhotoUrl']),
            const SizedBox(height: 12),
            _buildProofSection(context, 'Invoice Photo', loadData['invoicePhotoUrl']),
            const SizedBox(height: 12),
            _buildProofSection(context, 'Unloading Proof', loadData['unloadingProofUrl']),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 8),
                const Text('Load Completed', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                const Spacer(),
                Text('₹${loadData['price']}', style: const TextStyle(color: AppColors.primaryBlue, fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
            const Divider(height: 24),
            Text('${loadData['fromLocation']} → ${loadData['toLocation']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildInfoItem(Icons.category, loadData['material']),
                _buildInfoItem(Icons.fitness_center, loadData['weight'] ?? 'N/A'),
              ],
            ),
            if (loadData['driverName'] != null) ...[
              const Divider(height: 24),
              Row(
                children: [
                  const Icon(Icons.person, size: 16, color: Colors.grey),
                  const SizedBox(width: 8),
                  Text('Driver: ${loadData['driverName']}', style: const TextStyle(fontWeight: FontWeight.w500)),
                  const Spacer(),
                  if (loadData['driverPhone'] != null)
                    IconButton(
                      onPressed: () => launchUrl(Uri.parse('tel:${loadData['driverPhone']}')),
                      icon: const Icon(Icons.call, color: Colors.green),
                      style: IconButton.styleFrom(backgroundColor: Colors.green.withValues(alpha: 0.1)),
                    ),
                ],
              ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String text) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey),
          const SizedBox(width: 4),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  Widget _buildProofSection(BuildContext context, String title, String? imageUrl) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            imageUrl != null ? Icons.photo_camera_back : Icons.image_not_supported,
            color: imageUrl != null ? AppColors.primaryBlue : Colors.grey,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: imageUrl != null ? Colors.black : Colors.grey,
              ),
            ),
          ),
          if (imageUrl != null)
            TextButton(
              onPressed: () => _showFullScreenImage(context, imageUrl, title),
              child: const Text('View', style: TextStyle(fontWeight: FontWeight.bold)),
            )
          else
            const Text('Not Uploaded', style: TextStyle(color: Colors.grey, fontSize: 12)),
        ],
      ),
    );
  }

  void _showFullScreenImage(BuildContext context, String imageUrl, String title) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(title),
          ),
          body: Center(
            child: InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const CircularProgressIndicator(color: Colors.white);
                },
                errorBuilder: (context, error, stackTrace) => const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.broken_image, color: Colors.white54, size: 50),
                    SizedBox(height: 10),
                    Text('Failed to load image', style: TextStyle(color: Colors.white54)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
