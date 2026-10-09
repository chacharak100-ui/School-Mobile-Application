import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; 
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart'; // For SystemNavigator

import 'config/app_config.dart';
import 'screens/login_screen.dart';

// Global instance for local notifications
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize Local Notifications
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  
  const DarwinInitializationSettings initializationSettingsDarwin =
      DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );
  
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsDarwin,
  );
  
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // 2. Initialize AppConfig (Fetches Status & Schools)
  await AppConfig.init();

  // 3. Initialize Firebase
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    await setupFirebaseMessaging();
  } catch (e) {
    debugPrint("❌ Error initializing Firebase: $e");
  }

  runApp(const SchoolApp());
}

Future<void> setupFirebaseMessaging() async {
  FirebaseMessaging messaging = FirebaseMessaging.instance;
  NotificationSettings settings = await messaging.requestPermission(
    alert: true, badge: true, sound: true,
  );
  
  String? fcmToken = await messaging.getToken();
  debugPrint("📱 FCM DEVICE TOKEN: $fcmToken");

  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    if (message.notification != null) showNotification(message);
  });
}

Future<void> showNotification(RemoteMessage message) async {
  const AndroidNotificationDetails androidPlatformChannelSpecifics =
      AndroidNotificationDetails(
    'school_channel_id', 'School Notifications',
    channelDescription: 'Notifications for school updates',
    importance: Importance.max, priority: Priority.high,
    icon: '@mipmap/ic_launcher',
  );
  
  const NotificationDetails platformChannelSpecifics = NotificationDetails(
    android: androidPlatformChannelSpecifics,
  );

  await flutterLocalNotificationsPlugin.show(
    0,
    message.notification?.title ?? 'New Message',
    message.notification?.body ?? '',
    platformChannelSpecifics,
  );
}

class SchoolApp extends StatelessWidget {
  const SchoolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Mizora School App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0056B3)),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const AppInitializer(),
    );
  }
}

// Global App Initialization & Maintenance Gate
class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key});

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  @override
  void initState() {
    super.initState();
    // Small delay to ensure AppConfig has finished its initial sync if needed
    Future.delayed(const Duration(milliseconds: 800), () {
      _checkAppStatus();
    });
  }

  Future<void> _checkAppStatus() async {
    // Force a fresh check just in case
    await AppConfig.fetchGlobalAppStatus();

    if (mounted) {
      if (AppConfig.isAppInMaintenance()) {
        _showMaintenanceDialog(context);
      } else {
        _navigateToLogin();
      }
    }
  }

  void _navigateToLogin() {
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  void _showMaintenanceDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent closing by tapping outside
      builder: (BuildContext dialogContext) {
        return PopScope(
          canPop: false, // Prevent back button
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.build_rounded, color: Colors.orange.shade700, size: 30),
                ),
                const SizedBox(width: 15),
                const Expanded(
                  child: Text(
                    'Under Maintenance',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppConfig.globalMaintenanceMessage.isNotEmpty
                      ? AppConfig.globalMaintenanceMessage
                      : 'We are currently performing scheduled maintenance to improve our services. Please check back later.',
                  style: const TextStyle(fontSize: 16, height: 1.5),
                ),
                const SizedBox(height: 20),
                if (AppConfig.globalAndroidLink.isNotEmpty || AppConfig.globalIosLink.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.shade100),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.system_update_alt, color: Colors.blue.shade700),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'A new version might be available.',
                            style: TextStyle(color: Colors.blue.shade900, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            actions: [
              // Close App Button
              TextButton.icon(
                onPressed: () {
                  // Exit the app completely
                  SystemNavigator.pop();
                },
                icon: const Icon(Icons.close),
                label: const Text('Close App'),
                style: TextButton.styleFrom(foregroundColor: Colors.grey[600]),
              ),
              
              // Update Button (Only if links exist)
              if (AppConfig.globalAndroidLink.isNotEmpty || AppConfig.globalIosLink.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: () async {
                    final String? targetUrl = Theme.of(dialogContext).platform == TargetPlatform.iOS 
                        ? AppConfig.globalIosLink 
                        : AppConfig.globalAndroidLink;
                        
                    if (targetUrl != null && targetUrl.isNotEmpty) {
                      final Uri url = Uri.parse(targetUrl);
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url, mode: LaunchMode.externalApplication);
                      }
                    }
                  },
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Update Now'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text('Initializing...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}