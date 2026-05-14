import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'package:transify_app/core/localization/language_provider.dart';
import 'package:transify_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:transify_app/features/auth/presentation/screens/signup_screen.dart';
import 'package:transify_app/features/auth/presentation/screens/forgot_password_screen.dart';
import 'package:transify_app/features/load_owner/presentation/screens/owner_dashboard_screen.dart';
import 'package:transify_app/features/driver/presentation/screens/driver_dashboard_screen.dart';
import 'package:transify_app/features/admin/presentation/screens/admin_dashboard_screen.dart';
import 'package:transify_app/core/utils/snackbar_utils.dart';


class LoginScreen extends StatefulWidget {
  final String role;
  const LoginScreen({super.key, required this.role});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<LanguageProvider>(context);
    final isOwner = widget.role == 'Load Owner';

    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthAuthenticated) {
          _navigateToDashboard(context, state.role);
        } else if (state is AuthError) {
          SnackBarUtils.showError(context, state.message);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('${lang.translate('login')} - ${lang.translate(widget.role.toLowerCase().replaceAll(' ', '_'))}'),
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Center(child: Hero(tag: 'logo', child: Image.asset('assets/logo/logo.png', height: 100))),
              const SizedBox(height: 40),
              Text(
                '${lang.translate('login')} ${lang.translate('to_continue')}',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 30),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: lang.translate('phone_number'),
                  prefixIcon: const Icon(Icons.phone),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _passwordController,
                obscureText: _obscureText,
                keyboardType: isOwner ? TextInputType.number : TextInputType.text,
                maxLength: isOwner ? 4 : null,
                decoration: InputDecoration(
                  labelText: isOwner ? lang.translate('pin') : lang.translate('password'),
                  prefixIcon: Icon(isOwner ? Icons.lock_outline : Icons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(_obscureText ? Icons.visibility : Icons.visibility_off),
                    onPressed: () => setState(() => _obscureText = !_obscureText),
                  ),
                ),
              ),
              const SizedBox(height: 40),
              BlocBuilder<AuthBloc, AuthState>(
                builder: (context, state) {
                  return ElevatedButton(
                    onPressed: state is AuthLoading ? null : _onLogin,
                    child: state is AuthLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : Text(lang.translate('login')),
                  );
                },
              ),
              const SizedBox(height: 10),
              Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => ForgotPasswordScreen(role: widget.role)));
                  },
                  child: Text(lang.translate('forgot_password')),
                ),
              ),
              const SizedBox(height: 10),
              if (widget.role != 'Admin')
                Center(
                  child: TextButton(
                    onPressed: () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => SignupScreen(role: widget.role)));
                    },
                    child: Text('${lang.translate('dont_have_account')} ${lang.translate('signup')}'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _onLogin() {
    final phone = _phoneController.text.trim();
    final password = _passwordController.text.trim();

    context.read<AuthBloc>().add(LoginRequested(phone, password, widget.role));
  }

  void _navigateToDashboard(BuildContext context, String role) {
    Widget dashboard;
    switch (role) {
      case 'Load Owner':
        dashboard = const OwnerDashboardScreen();
        break;
      case 'Driver':
        dashboard = const DriverDashboardScreen();
        break;
      case 'Admin':
        dashboard = const AdminDashboardScreen();
        break;
      default:
        return;
    }
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => dashboard), (route) => false);
  }
}
