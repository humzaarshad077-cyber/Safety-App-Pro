import 'dart:async';
import 'dart:convert';
import 'package:googleapis_auth/auth_io.dart';

import 'secrets.dart';

class FCMService {
  static Future<void> sendPushNotification({
    required String targetFCMToken,
    required String senderPhone,
    required String message,
  }) async {
    AutoRefreshingAuthClient? authClient;
    try {
      if (fcmServiceAccountJson.trim().isEmpty) {
        print("❌ FCM Service Error: Service account JSON is empty.");
        return;
      }

      final accountCredentials =
          ServiceAccountCredentials.fromJson(fcmServiceAccountJson);
      final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];
      authClient = await clientViaServiceAccount(accountCredentials, scopes)
          .timeout(const Duration(seconds: 4));

      final Map<String, dynamic> keyMap = jsonDecode(fcmServiceAccountJson);
      final String projectId = keyMap['project_id'];
      final String endpoint =
          'https://fcm.googleapis.com/v1/projects/$projectId/messages:send';

      bool isLocationReq =
          (message == 'LOCATION_REQUEST' || message == 'location_request');
      bool isChatMsg = message.startsWith('CHAT_MSG:');
      bool isIncomingCall = message.startsWith('INCOMING_CALL:');

      String cleanBody = message;
      if (isChatMsg) {
        cleanBody = message.replaceFirst('CHAT_MSG:', '').trim();
      } else if (isIncomingCall) {
        cleanBody = message.replaceFirst('INCOMING_CALL:', '').trim();
      }

      String payloadType = isLocationReq
          ? 'location_request'
          : (isIncomingCall
              ? 'incoming_call'
              : (isChatMsg ? 'chat_message' : 'sos_alert'));

      String notifTitle = isLocationReq
          ? 'Location Ping'
          : (isIncomingCall
              ? '📞 Incoming Emergency Call from $senderPhone'
              : (isChatMsg
                  ? '💬 New Message from $senderPhone'
                  : '🚨 EMERGENCY SOS FROM $senderPhone'));

      // 1. PACKET 1: HIGH-PRIORITY DATA PAYLOAD (Wakes up background isolate immediately)
      final Map<String, dynamic> dataPayload = {
        'message': {
          'token': targetFCMToken,
          'data': {
            'type': payloadType,
            'title': notifTitle,
            'body': cleanBody,
            'message': cleanBody,
            'sender': senderPhone,
            'action': payloadType,
          },
          'android': {
            'priority': 'high',
          }
        }
      };

      final res1 = await authClient
          .post(
            Uri.parse(endpoint),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(dataPayload),
          )
          .timeout(const Duration(seconds: 4));
      print("✅ FCM DATA PACKET ($payloadType) STATUS: ${res1.statusCode}");

      // 2. PACKET 2: DIRECT MAIN-SCREEN / LOCK-SCREEN HEADS-UP BANNER
      if (!isLocationReq) {
        final Map<String, dynamic> visualNotificationPayload = {
          'message': {
            'token': targetFCMToken,
            'notification': {
              'title': notifTitle,
              'body': isIncomingCall
                  ? 'Tap here to Answer In-App Live Voice Call!'
                  : (isChatMsg
                      ? cleanBody
                      : 'Tap immediately to view live location & respond!'),
            },
            'data': {
              'type': payloadType,
              'sender': senderPhone,
              'message': cleanBody,
              'body': cleanBody,
            },
            'android': {
              'priority': 'high',
              'notification': {
                'channel_id': 'safety_high_priority_channel',
                'default_sound': true,
                'default_vibrate_timings': true,
                'visibility': 'PUBLIC',
              }
            }
          }
        };

        final res2 = await authClient
            .post(
              Uri.parse(endpoint),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(visualNotificationPayload),
            )
            .timeout(const Duration(seconds: 4));
        print("✅ FCM VISUAL BANNER STATUS: ${res2.statusCode}");
      }
    } catch (e) {
      print("❌ FCM Service Error: $e");
    } finally {
      authClient?.close();
    }
  }
}