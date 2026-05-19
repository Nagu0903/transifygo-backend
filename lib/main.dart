import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'core/localization/language_provider.dart';
import 'features/auth/presentation/screens/splash_screen.dart';
import 'features/auth/presentation/bloc/auth_bloc.dart';
import 'features/load_owner/presentation/bloc/load_bloc.dart';
import 'core/services/notification_service.dart';
import 'firebase_options.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint("Handling a background message: ${message.messageId}");
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // FORCE CLEAN FIREBASE AUTH STATE
  try {
    debugPrint('[FIREBASE_AUTH] Wiping legacy session if any...');
    await FirebaseAuth.instance.signOut();
    debugPrint('[FIREBASE_AUTH] Attempting fresh Anonymous Sign-In...');
    await FirebaseAuth.instance.signInAnonymously();
    debugPrint('[FIREBASE_AUTH] Success: ${FirebaseAuth.instance.currentUser?.uid}');
  } catch (e) {
    debugPrint('[FIREBASE_AUTH] Init Error: $e');
  }

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Initialize Notifications
  await NotificationService.initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
      ],
      child: const TransifyApp(),
    ),
  );
}

class TransifyApp extends StatelessWidget {
  const TransifyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (context) => AuthBloc()),
        BlocProvider(create: (context) => LoadBloc()),
      ],
      child: Consumer<LanguageProvider>(
        builder: (context, langProvider, child) {
          return MaterialApp(
            title: 'TransifyGo',
            debugShowCheckedModeBanner: false,
            navigatorKey: navigatorKey,
            theme: AppTheme.lightTheme,
            locale: langProvider.currentLocale,
            home: const SplashScreen(),
          );
        },
      ),
    );
  }
}
