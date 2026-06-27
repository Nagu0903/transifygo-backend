import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:transify_app/core/constants/app_colors.dart';
import 'package:transify_app/features/load_owner/presentation/bloc/load_bloc.dart';

class CompleteLoadSheet extends StatefulWidget {
  final String loadId;

  const CompleteLoadSheet({super.key, required this.loadId});

  @override
  State<CompleteLoadSheet> createState() => _CompleteLoadSheetState();
}

class _CompleteLoadSheetState extends State<CompleteLoadSheet> {
  final ImagePicker _picker = ImagePicker();
  
  File? _deliveryPhoto;
  File? _invoicePhoto;
  File? _unloadingProof;

  bool _isUploading = false;
  double _uploadProgress = 0.0;

  Future<void> _pickImage(int type) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 50, // Compress image to save bandwidth
      );

      if (image != null) {
        setState(() {
          if (type == 1) _deliveryPhoto = File(image.path);
          if (type == 2) _invoicePhoto = File(image.path);
          if (type == 3) _unloadingProof = File(image.path);
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick image: $e')),
      );
    }
  }

  Future<String?> _uploadSingleImage(File file, String name) async {
    // 1. Ensure authenticated session for secure Storage Rules via Anonymous Auth
    try {
      if (FirebaseAuth.instance.currentUser == null) {
        debugPrint('[FIREBASE_AUTH] No current user. Attempting anonymous sign-in...');
        final userCredential = await FirebaseAuth.instance.signInAnonymously();
        if (userCredential.user == null) {
          throw Exception('Anonymous sign-in returned null user.');
        }
        debugPrint('[FIREBASE_AUTH] Successfully signed in anonymously: ${userCredential.user?.uid}');
      } else {
        debugPrint('[FIREBASE_AUTH] Already signed in: ${FirebaseAuth.instance.currentUser?.uid}');
      }
    } catch (e) {
      debugPrint('[FIREBASE_AUTH] Failed to sign in securely: $e');
      throw Exception('Authentication failed. Cannot upload files securely. Please ensure Anonymous Authentication is enabled in your Firebase Console.');
    }

    // 2. Map frontend names to standard folder names
    String proofType = 'other';
    final lowerName = name.toLowerCase();
    if (lowerName.contains('delivery')) proofType = 'delivery';
    if (lowerName.contains('invoice')) proofType = 'invoice';
    if (lowerName.contains('unloading')) proofType = 'unloading';

    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries) {
      try {
        final safeLoadId = widget.loadId.trim().isEmpty ? 'unknown_load' : widget.loadId.trim();
        // IMPORTANT: Must start with 'loads/' to match Firebase Storage Security Rules
        final bucketPath = 'loads/$safeLoadId/$proofType/${DateTime.now().millisecondsSinceEpoch}.jpg';
        final ref = FirebaseStorage.instance.ref().child(bucketPath);

        debugPrint('[FIREBASE_STORAGE] Attempting upload to bucket: ${FirebaseStorage.instance.bucket}');
        debugPrint('[FIREBASE_STORAGE] Upload path: $bucketPath (Attempt ${retryCount + 1}/$maxRetries)');

        final metadata = SettableMetadata(
          contentType: 'image/jpeg',
          customMetadata: {'picked-file-path': file.path},
        );

        final fileBytes = await file.readAsBytes();
        final uploadTask = ref.putData(fileBytes, metadata);
        
        // Ensure upload completely finishes before asking for URL
        final snapshot = await uploadTask.whenComplete(() => null);
        
        if (snapshot.state != TaskState.success) {
          throw Exception('Upload task failed with state: ${snapshot.state}. Check Firebase Storage Rules.');
        }
        
        // Wait a tiny bit to ensure propagation
        await Future.delayed(const Duration(milliseconds: 500));
        
        // Verify object exists implicitly by fetching URL from snapshot ref
        final downloadUrl = await snapshot.ref.getDownloadURL();
        debugPrint('[FIREBASE_STORAGE] Upload success. URL: $downloadUrl');
        return downloadUrl;
      } catch (e) {
        retryCount++;
        debugPrint('[FIREBASE_STORAGE] Upload failed for $name: $e');
        
        if (retryCount >= maxRetries) {
          throw Exception('Failed to upload $name proof after $maxRetries attempts. Please check connection and Firebase Storage Rules. Error: $e');
        }
        
        // Wait before retrying (exponential backoff)
        await Future.delayed(Duration(seconds: retryCount * 2));
      }
    }
    return null;
  }

  Future<void> _submitCompletion() async {
    // We allow optional uploads per requirements: "optional"
    setState(() {
      _isUploading = true;
      _uploadProgress = 0.1;
    });

    try {
      String? deliveryUrl;
      String? invoiceUrl;
      String? unloadingUrl;

      if (_deliveryPhoto != null) {
        deliveryUrl = await _uploadSingleImage(_deliveryPhoto!, 'delivery');
        setState(() => _uploadProgress = 0.4);
      }
      
      if (_invoicePhoto != null) {
        invoiceUrl = await _uploadSingleImage(_invoicePhoto!, 'invoice');
        setState(() => _uploadProgress = 0.7);
      }
      
      if (_unloadingProof != null) {
        unloadingUrl = await _uploadSingleImage(_unloadingProof!, 'unloading');
        setState(() => _uploadProgress = 0.9);
      }

      if (!mounted) return;

      final extraData = <String, dynamic>{};
      if (deliveryUrl != null) extraData['deliveryPhotoUrl'] = deliveryUrl;
      if (invoiceUrl != null) extraData['invoicePhotoUrl'] = invoiceUrl;
      if (unloadingUrl != null) extraData['unloadingProofUrl'] = unloadingUrl;

      // Trigger BLOC event
      context.read<LoadBloc>().add(UpdateLoadStatusRequested(
        widget.loadId,
        'completed',
        extraData: extraData,
      ));

      setState(() => _uploadProgress = 1.0);
      
    } catch (e) {
      if (!mounted) return;
      setState(() => _isUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Upload failed: $e. Please try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<LoadBloc, LoadState>(
      listener: (context, state) {
        if (state is LoadSuccess) {
          if (mounted) {
            Navigator.pop(context, true); // Close sheet and return success
          }
        } else if (state is LoadError) {
          setState(() => _isUploading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
      },
      child: Container(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Complete Load',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Upload proof of delivery (Optional but recommended).',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 24),

              // Upload Buttons
              _buildUploadRow('Delivery Photo', 1, _deliveryPhoto),
              const SizedBox(height: 12),
              _buildUploadRow('Invoice Photo', 2, _invoicePhoto),
              const SizedBox(height: 12),
              _buildUploadRow('Unloading Proof', 3, _unloadingProof),
              
              const SizedBox(height: 30),

              if (_isUploading) ...[
                LinearProgressIndicator(value: _uploadProgress, color: AppColors.primaryBlue),
                const SizedBox(height: 10),
                Center(child: Text('Uploading... ${( _uploadProgress * 100).toInt()}%', style: const TextStyle(color: Colors.grey))),
                const SizedBox(height: 20),
              ],

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isUploading ? null : _submitCompletion,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(
                    _isUploading ? 'Please Wait...' : 'Mark as Completed',
                    style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUploadRow(String title, int type, File? file) {
    return InkWell(
      onTap: _isUploading ? null : () => _pickImage(type),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              file != null ? Icons.check_circle : Icons.camera_alt,
              color: file != null ? Colors.green : Colors.grey,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  color: file != null ? Colors.black : Colors.grey.shade700,
                  fontWeight: file != null ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            if (file != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.file(file, width: 40, height: 40, fit: BoxFit.cover),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.red, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: _isUploading ? null : () {
                  setState(() {
                    if (type == 1) _deliveryPhoto = null;
                    if (type == 2) _invoicePhoto = null;
                    if (type == 3) _unloadingProof = null;
                  });
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
