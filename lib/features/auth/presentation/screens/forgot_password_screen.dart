import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:transify_app/core/localization/language_provider.dart';
import 'package:transify_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:transify_app/core/utils/snackbar_utils.dart';


class ForgotPasswordScreen extends StatefulWidget {
  final String role;
  const ForgotPasswordScreen({super.key, required this.role});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _phoneController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final isOwner = widget.role == 'Load Owner';

    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthInitial && _phoneController.text.isNotEmpty) {
          SnackBarUtils.showSuccess(context, 'Password reset successful! Please login.');
          Navigator.pop(context);
        } else if (state is AuthError) {
          SnackBarUtils.showError(context, state.message);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(lang.translate('reset_password'))),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(
                lang.translate('forgot_password_instruction'),
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: lang.translate('phone_number'),
                  prefixIcon: const Icon(Icons.phone),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _newPasswordController,
                obscureText: true,
                keyboardType: isOwner ? TextInputType.number : TextInputType.text,
                maxLength: isOwner ? 4 : null,
                decoration: InputDecoration(
                  labelText: isOwner ? 'New 4-Digit PIN' : 'New Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _confirmPasswordController,
                obscureText: true,
                keyboardType: isOwner ? TextInputType.number : TextInputType.text,
                maxLength: isOwner ? 4 : null,
                decoration: InputDecoration(
                  labelText: isOwner ? 'Confirm New PIN' : 'Confirm New Password',
                  prefixIcon: const Icon(Icons.lock_reset),
                ),
              ),
              const SizedBox(height: 40),
              BlocBuilder<AuthBloc, AuthState>(
                builder: (context, state) {
                  return SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: state is AuthLoading ? null : _onReset,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade800,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: state is AuthLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text(
                              'Reset Password',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onReset() {
    final phone = _phoneController.text.trim();
    final newPass = _newPasswordController.text.trim();
    final confirmPass = _confirmPasswordController.text.trim();

    if (phone.isEmpty || newPass.isEmpty || confirmPass.isEmpty) {
      SnackBarUtils.showWarning(context, 'Please fill all fields');
      return;
    }

    if (newPass != confirmPass) {
      SnackBarUtils.showWarning(context, 'Passwords do not match');
      return;
    }

    if (widget.role == 'Load Owner' && newPass.length != 4) {
      SnackBarUtils.showWarning(context, 'PIN must be 4 digits');
      return;
    }

    context.read<AuthBloc>().add(ResetPasswordRequested(
      phone: phone,
      role: widget.role,
      newPassword: newPass,
    ));
  }
}
