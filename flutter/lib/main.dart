import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'services/notification_service.dart';
import 'screens/home_screen.dart';
import 'screens/manage_alarms_screen.dart';

// Global navigator key so we can route from notification tap callbacks
// which run outside the widget tree.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ── Notification tap handler (top-level, required for background callbacks) ──

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  // Minimal handler — the foreground handler below does the actual routing.
}

void onNotificationTap(NotificationResponse response) {
  navigatorKey.currentState?.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const ManageAlarmsScreen()),
    (route) => route.isFirst,
  );
}

// ── Main ──────────────────────────────────────────────────────────────────────

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await NotificationService.instance.init(onNotificationTap: onNotificationTap);

  runApp(const AlarmApp());
}

class AlarmApp extends StatelessWidget {
  const AlarmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Remind Me Pls',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.white,
          brightness: Brightness.dark,
        ).copyWith(surface: Colors.black, onSurface: Colors.white),
        fontFamily: 'SF Pro Display',
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
