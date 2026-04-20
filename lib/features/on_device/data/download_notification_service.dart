import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'models/model_download_progress.dart';

class DownloadNotificationService {
  static const String channelId = 'model_downloads';
  static const String channelName = 'Model Downloads';
  static const String channelDescription = 'Notifications for AI model downloads';

  final FlutterLocalNotificationsPlugin _notifications = FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(android: androidInit, iOS: darwinInit);

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        // Handle notification click if needed
      },
    );

    // Create the channel for Android
    const androidChannel = AndroidNotificationChannel(
      channelId,
      channelName,
      description: channelDescription,
      importance: Importance.low, // Use low to avoid annoying sound for progress updates
      showBadge: false,
      enableVibration: false,
      playSound: false,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);
  }

  Future<void> showProgressNotification({
    required int id,
    required String modelName,
    required ModelDownloadProgress progress,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.low,
      priority: Priority.low,
      onlyAlertOnce: true,
      showProgress: true,
      maxProgress: 100,
      progress: (progress.fraction * 100).toInt(),
      ongoing: true, // Keep notification visible during download
      category: AndroidNotificationCategory.progress,
    );

    final darwinDetails = DarwinNotificationDetails(
      presentAlert: false,
      presentBadge: false,
      presentSound: false,
      subtitle: modelName,
    );

    final details = NotificationDetails(android: androidDetails, iOS: darwinDetails);

    await _notifications.show(
      id,
      'Downloading $modelName',
      '${(progress.fraction * 100).toStringAsFixed(1)}% • ${progress.speedFormatted} • ETA: ${progress.etaFormatted}',
      details,
    );
  }

  Future<void> showCompleteNotification({
    required int id,
    required String modelName,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      ongoing: false,
    );

    const details = NotificationDetails(android: androidDetails);

    await _notifications.show(
      id,
      'Download Complete',
      '$modelName is ready to use.',
      details,
    );
  }

  Future<void> showFailedNotification({
    required int id,
    required String modelName,
    required String error,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      ongoing: false,
    );

    const details = NotificationDetails(android: androidDetails);

    await _notifications.show(
      id,
      'Download Failed',
      'Failed to download $modelName: $error',
      details,
    );
  }

  Future<void> cancelNotification(int id) async {
    await _notifications.cancel(id);
  }
}
