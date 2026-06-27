import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:transify_app/core/constants/app_colors.dart';
import 'package:transify_app/features/load_owner/presentation/bloc/load_bloc.dart';
import 'package:transify_app/core/utils/snackbar_utils.dart';
import 'package:url_launcher/url_launcher.dart';

class PaymentManagementSection extends StatefulWidget {
  final Map<String, dynamic> loadData;

  const PaymentManagementSection({super.key, required this.loadData});

  @override
  State<PaymentManagementSection> createState() => _PaymentManagementSectionState();
}

class _PaymentManagementSectionState extends State<PaymentManagementSection> {
  late Map<String, dynamic> _localData;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _localData = Map.from(widget.loadData);
  }

  void _showUpdateDialog() {
    final totalCtrl = TextEditingController(text: _localData['totalAmount']?.toString() ?? '');
    final paidCtrl = TextEditingController(); // Start empty for incremental payment
    final notesCtrl = TextEditingController(text: _localData['paymentNotes'] ?? '');
    String selectedMethod = _localData['paymentMethod'] ?? '';
    if (selectedMethod.isEmpty) selectedMethod = 'cash';
    File? selectedScreenshot;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return StatefulBuilder(builder: (context, setModalState) {
          Future<void> pickImage() async {
            final picker = ImagePicker();
            final pickedFile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
            if (pickedFile != null) {
              setModalState(() => selectedScreenshot = File(pickedFile.path));
            }
          }

          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
              left: 16, right: 16, top: 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Update Payment', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  
                  TextField(
                    controller: totalCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Total Amount (₹)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  
                  TextField(
                    controller: paidCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Amount to Pay Now (₹)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  
                  DropdownButtonFormField<String>(
                    initialValue: selectedMethod,
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('Cash')),
                      DropdownMenuItem(value: 'upi', child: Text('UPI')),
                      DropdownMenuItem(value: 'bank_transfer', child: Text('Bank Transfer')),
                    ],
                    onChanged: (v) => setModalState(() => selectedMethod = v!),
                    decoration: const InputDecoration(labelText: 'Payment Method', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),
                  
                  TextField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(labelText: 'Notes (Optional)', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 12),

                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.image, color: selectedScreenshot != null ? Colors.green : Colors.grey),
                    title: Text(selectedScreenshot != null ? 'Screenshot Selected' : 'Upload Screenshot (Optional)'),
                    trailing: TextButton(
                      onPressed: pickImage,
                      child: const Text('Select'),
                    ),
                  ),

                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _isUploading ? null : () async {
                        final total = double.tryParse(totalCtrl.text) ?? 0;
                        final paid = double.tryParse(paidCtrl.text) ?? 0;
                        
                        setModalState(() => _isUploading = true);
                        String? screenshotUrl = _localData['paymentScreenshotUrl'];
                        
                        try {
                          if (selectedScreenshot != null) {
                            final safeLoadId = _localData['_id']?.toString() ?? 'unknown_load';
                            final bucketPath = 'loads/$safeLoadId/payment_${DateTime.now().millisecondsSinceEpoch}.jpg';
                            final ref = FirebaseStorage.instance.ref().child(bucketPath);
                            final metadata = SettableMetadata(contentType: 'image/jpeg');
                            
                            final fileBytes = await selectedScreenshot!.readAsBytes();
                            final uploadTask = ref.putData(fileBytes, metadata);
                            final snapshot = await uploadTask.whenComplete(() => null);
                            if (snapshot.state != TaskState.success) throw Exception('Upload failed');
                            await Future.delayed(const Duration(milliseconds: 500));
                            screenshotUrl = await snapshot.ref.getDownloadURL();
                          }
                          
                          if (!context.mounted) return;
                          
                          final payload = <String, dynamic>{
                            'totalAmount': total,
                            'enteredAmount': paid,
                            'paymentMethod': selectedMethod,
                            'paymentNotes': notesCtrl.text,
                          };
                          
                          if (screenshotUrl != null) {
                            payload['paymentScreenshotUrl'] = screenshotUrl;
                          }

                          context.read<LoadBloc>().add(UpdatePaymentStatusRequested(_localData['_id'], payload));
                          Navigator.pop(ctx);
                        } catch (e) {
                          setModalState(() => _isUploading = false);
                          if (context.mounted) SnackBarUtils.showError(context, 'Failed to update: $e');
                        }
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue),
                      child: _isUploading 
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Save Payment', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<LoadBloc, LoadState>(
      listener: (context, state) {
        if (state is LoadSuccess && state.message == 'Payment updated successfully') {
          SnackBarUtils.showSuccess(context, 'Payment details updated!');
          // Refresh list triggers on pop, for now just advise to refresh
        } else if (state is LoadError) {
          SnackBarUtils.showError(context, state.message);
        }
      },
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        elevation: 2,
        margin: const EdgeInsets.only(top: 20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Payment Status', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  _buildPaymentBadge(_localData['paymentStatus'] ?? 'pending'),
                ],
              ),
              const Divider(height: 24),
              _buildRow('Total Amount', '₹${_localData['totalAmount'] ?? '0'}'),
              const SizedBox(height: 8),
              _buildRow('Paid Amount', '₹${_localData['paidAmount'] ?? '0'}', valueColor: Colors.green),
              const SizedBox(height: 8),
              _buildRow('Remaining Balance', '₹${_localData['remainingAmount'] ?? '0'}', valueColor: Colors.red),
              const SizedBox(height: 8),
              _buildRow('Payment Method', (_localData['paymentMethod'] ?? 'N/A').toString().toUpperCase()),
              
              if (_localData['paymentHistory'] != null && (_localData['paymentHistory'] as List).isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildRow('Last Payment', '₹${(_localData['paymentHistory'] as List).last['amount']}'),
              ],
              
              if (_localData['paymentScreenshotUrl'] != null) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => launchUrl(Uri.parse(_localData['paymentScreenshotUrl'])),
                  icon: const Icon(Icons.receipt),
                  label: const Text('View Receipt'),
                )
              ],

              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _showUpdateDialog,
                  icon: const Icon(Icons.edit),
                  label: const Text('Manage Payment'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade600)),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: valueColor ?? Colors.black)),
      ],
    );
  }

  Widget _buildPaymentBadge(String status) {
    Color color;
    switch (status) {
      case 'paid': color = Colors.green; break;
      case 'partial': color = Colors.orange; break;
      default: color = Colors.red;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: color)),
      child: Text(status.toUpperCase(), style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
    );
  }
}
