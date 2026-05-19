import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:transify_app/core/network/api_service.dart';
import 'package:transify_app/core/services/session_service.dart';
import 'package:transify_app/main.dart';
import 'package:transify_app/features/notifications/presentation/screens/notifications_screen.dart';
import 'package:transify_app/features/load_owner/presentation/screens/completed_load_details_screen.dart' as transify_completed;
import 'dart:convert';

class NotificationService {
  static final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  static final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  static final ApiService _api = ApiService();

  static final StreamController<String> onNotificationReceived = StreamController<String>.broadcast();

  static Future<void> initialize() async {
    // 1. Request FCM Permission
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('User granted notification permission');
    }

    // 2. Request Android 13+ Local Notification Permission
    if (defaultTargetPlatform == TargetPlatform.android) {
      final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
          _localNotifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      await androidImplementation?.requestNotificationsPermission();

      // Create the Notification Channel explicitly (required for Android 8.0+)
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'transify_go_channel',
        'TransifyGo Alerts',
        description: 'This channel is used for important notifications.',
        importance: Importance.max,
      );

      await androidImplementation?.createNotificationChannel(channel);
    }

    // 3. Local Notifications Setup
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/launcher_icon');
    
    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
    );

    await _localNotifications.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (details) {
        if (details.payload != null) {
          try {
            final data = jsonDecode(details.payload!);
            _handleNotificationClick(payloadData: data);
            return;
          } catch (e) {
            debugPrint('Error parsing local notification payload: $e');
          }
        }
        _handleNotificationClick();
      },
    );

    // 4. Handle Foreground Messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Foreground Message: ${message.notification?.title}');
      
      final type = message.data['type'];
      if (type != null) {
        onNotificationReceived.add(type);
      }
      
      _showLocalNotification(message);
    });

    // 5. Handle Background/Terminated Message Clicks
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('App opened from background message');
      _handleNotificationClick(payloadData: message.data);
    });

    // 6. Handle App launched from terminated state via notification
    RemoteMessage? initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('App launched from terminated state via message');
      // Adding a slight delay to ensure UI is built before navigating
      Future.delayed(const Duration(milliseconds: 500), () {
        _handleNotificationClick(payloadData: initialMessage.data);
      });
    }

    // 7. Update Token
    await updateToken();
  }

  static void _handleNotificationClick({Map<String, dynamic>? payloadData}) {
    final context = navigatorKey.currentContext;
    if (context != null) {
      if (payloadData != null && payloadData['type'] == 'load_completed' && payloadData['loadData'] != null) {
        try {
          final loadData = jsonDecode(payloadData['loadData']);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => transify_completed.CompletedLoadDetailsScreen(loadData: loadData)),
          );
          return;
        } catch (e) {
          debugPrint('Error parsing loadData from notification: $e');
        }
      }

      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const NotificationsScreen()),
      );
    } else {
      debugPrint('Navigator context is null, cannot route to NotificationsScreen');
    }
  }

  static Future<void> updateToken() async {
    try {
      String? token = await _fcm.getToken();
      if (token != null) {
        final session = await SessionService.getSession();
        final uid = session['uid'];
        if (uid != null) {
          debugPrint('FCM Token: $token');
          await _api.post('/notifications/token', {
            'userId': uid,
            'fcmToken': token,
          });
        }
      }
    } catch (e) {
      debugPrint('Failed to update FCM token: $e');
    }
  }

  static Future<void> _showLocalNotification(RemoteMessage message) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'transify_go_channel',
      'TransifyGo Alerts',
      channelDescription: 'This channel is used for important notifications.',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: true,
      enableVibration: true,
      playSound: true,
    );

    const NotificationDetails platformDetails = NotificationDetails(android: androidDetails);

    await _localNotifications.show(
      id: message.hashCode,
      title: message.notification?.title,
      body: message.notification?.body,
      notificationDetails: platformDetails,
      payload: jsonEncode(message.data),
    );
  }
}
