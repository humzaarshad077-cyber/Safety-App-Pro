import 'dart:async';
import 'dart:ui';
import 'dart:math';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

import 'fcm_service.dart';

// 🔥 HELPER: Get both +923... and 03... formats so numbers ALWAYS match!
List<String> getPhoneVariants(String rawPhone) {
  String clean = rawPhone.replaceAll(RegExp(r'[\s\-\(\)]'), '').trim();
  if (clean.isEmpty) return [];
  Set<String> variants = {clean};
  if (clean.startsWith('+92') && clean.length >= 12) {
    variants.add('0${clean.substring(3)}');
  } else if (clean.startsWith('92') && clean.length >= 11) {
    variants.add('+92${clean.substring(2)}');
    variants.add('0${clean.substring(2)}');
  } else if (clean.startsWith('03') && clean.length >= 10) {
    variants.add('+92${clean.substring(1)}');
  }
  return variants.toList();
}

Future<void> initializeBackgroundService() async {
  final service = FlutterBackgroundService();
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: true,
      isForegroundMode: true,
      initialNotificationTitle: 'Safety App Pro',
      initialNotificationContent: 'System Monitoring Active...',
    ),
    iosConfiguration: IosConfiguration(autoStart: true, onForeground: onStart),
  );
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  await Firebase.initializeApp();

  bool uiHandledSOS = false;
  bool isBgAlarmRinging = false;
  int silencedUntilEpochMs = 0;

  service.on('uiHandledSOS').listen((event) {
    uiHandledSOS = true;
  });

  // 🔥 INSTANT CROSS-ISOLATE ALARM STOPPER (With 30s Anti-Restart Lock)
  Future<void> forceStopBgAlarm() async {
    isBgAlarmRinging = false;
    silencedUntilEpochMs = DateTime.now().millisecondsSinceEpoch + 30000;
    try {
      await FlutterRingtonePlayer().stop();
    } catch (_) {}
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'Safety App Pro',
        content: 'System Monitoring Active...',
      );
    }
  }

  // Safe single-instance alarm starter (Never creates duplicate un-stoppable alarms!)
  Future<void> safePlayBgAlarm({bool isRingtone = false}) async {
    int nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs < silencedUntilEpochMs) return;
    if (isBgAlarmRinging) return;

    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (prefs.getBool('stop_alarm_flag') == true) return;

    isBgAlarmRinging = true;
    try {
      await FlutterRingtonePlayer().stop();
      if (isRingtone) {
        FlutterRingtonePlayer().playRingtone(looping: true);
      } else {
        FlutterRingtonePlayer().playAlarm(volume: 1.0, looping: true, asAlarm: true);
      }
    } catch (_) {}
  }

  service.on('stopAlarm').listen((event) async {
    await forceStopBgAlarm();
  });

  // Fast 500ms watchdog to immediately catch silence button press from UI or Notification
  Timer.periodic(const Duration(milliseconds: 500), (_) async {
    if (!isBgAlarmRinging) return;
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      if (prefs.getBool('stop_alarm_flag') == true) {
        await forceStopBgAlarm();
      }
    } catch (_) {}
  });

  // 1. OFFLINE P2P MESH RECEIVER
  final Nearby nearby = Nearby();
  void _startMeshReceiver() async {
    try {
      await nearby.stopAllEndpoints();
      await nearby.stopDiscovery();
      await nearby.startDiscovery(
        "Rescuer",
        Strategy.P2P_CLUSTER,
        serviceId: "com.safetyapp.mesh",
        onEndpointFound: (id, name, endpointInfo) {
          if (name.startsWith("SOS_")) {
            nearby.requestConnection(
              "Rescuer",
              id,
              onConnectionInitiated: (id, info) => nearby.acceptConnection(
                id,
                onPayLoadRecieved: (endId, payload) async {
                  if (payload.bytes != null) {
                    String msg = utf8.decode(payload.bytes!);
                    String sender = name.replaceAll("SOS_", "");
                    SharedPreferences prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('stop_alarm_flag', false);
                    silencedUntilEpochMs = 0;

                    if (service is AndroidServiceInstance) {
                      service.setForegroundNotificationInfo(
                        title: '🚨 OFFLINE MESH SOS FROM $sender!',
                        content: msg,
                      );
                    }
                    await safePlayBgAlarm(isRingtone: false);
                    service.invoke('showSOSDialog', {'from': sender, 'message': msg});
                  }
                },
              ),
              onConnectionResult: (id, status) {},
              onDisconnected: (id) => _startMeshReceiver(),
            );
          }
        },
        onEndpointLost: (id) {},
      );
    } catch (e) {}
  }

  _startMeshReceiver();
  service.on('restartMesh').listen((event) => _startMeshReceiver());

  // 2. DYNAMIC FIRESTORE LISTENERS (Location, SOS & In-App Calls)
  String? boundPhone;
  List<StreamSubscription> activeSubs = [];

  void _bindFirestoreListeners(String phone) {
    if (boundPhone == phone) return;
    boundPhone = phone;
    for (var s in activeSubs) {
      s.cancel();
    }
    activeSubs.clear();

    List<String> variants = getPhoneVariants(phone);
    for (String vPhone in variants) {
      var locSub = FirebaseFirestore.instance
          .collection('location_requests')
          .doc(vPhone)
          .snapshots()
          .listen((snapshot) async {
        if (snapshot.exists && snapshot.data() != null) {
          var data = snapshot.data() as Map<String, dynamic>;
          if (data['status'] == 'pending') {
            await fulfillLocationRequestEverywhere(vPhone);
          }
        }
      });
      activeSubs.add(locSub);

      var alertSub = FirebaseFirestore.instance
          .collection('active_alerts')
          .doc(vPhone)
          .snapshots()
          .listen((snapshot) async {
        if (snapshot.exists && snapshot.data() != null) {
          var data = snapshot.data() as Map<String, dynamic>;
          if (data['status'] == 'active') {
            if (DateTime.now().millisecondsSinceEpoch < silencedUntilEpochMs) return;
            if (service is AndroidServiceInstance) {
              service.setForegroundNotificationInfo(
                title: '🚨 EMERGENCY SOS FROM ${data['from']}!',
                content: 'Tap notification to open Safety App Pro & view alert!',
              );
            }
            await safePlayBgAlarm(isRingtone: false);
            service.invoke('showSOSDialog', data);
          }
        } else {
          await forceStopBgAlarm();
        }
      });
      activeSubs.add(alertSub);

      var callSub = FirebaseFirestore.instance
          .collection('active_calls')
          .doc(vPhone)
          .snapshots()
          .listen((snapshot) async {
        if (snapshot.exists && snapshot.data() != null) {
          var data = snapshot.data() as Map<String, dynamic>;
          if (data['status'] == 'ringing') {
            if (DateTime.now().millisecondsSinceEpoch < silencedUntilEpochMs) return;
            String caller = data['callerName'] ?? data['caller'] ?? 'Emergency Contact';
            if (service is AndroidServiceInstance) {
              service.setForegroundNotificationInfo(
                title: '📞 INCOMING CALL: $caller',
                content: 'Tap to answer In-App Live Voice Call!',
              );
            }
            await safePlayBgAlarm(isRingtone: true);
            service.invoke('incomingCall', data);
          } else if (data['status'] == 'ended' || data['status'] == 'connected') {
            await forceStopBgAlarm();
          }
        } else {
          await forceStopBgAlarm();
        }
      });
      activeSubs.add(callSub);
    }
  }

  // ============================================================================
  // 3. CALIBRATED HARDWARE SENSORS (No False Trigger on Pickup; Triggers on 3 Firm Shakes!)
  // ============================================================================
  bool isCooldown = false;
  int shakePeakCount = 0;
  int firstShakeTimestampMs = 0;
  int lastPeakTimestampMs = 0;

  accelerometerEventStream().listen((AccelerometerEvent event) {
    if (isCooldown) return;
    double magnitude = sqrt(pow(event.x, 2) + pow(event.y, 2) + pow(event.z, 2));

    // Only count strong, deliberate shakes or hard impacts (> 32.0 m/s²).
    // Normal phone pickup/walking is 9.8 to 20.0 m/s², so it will NEVER false-trigger!
    if (magnitude > 32.0) {
      int nowMs = DateTime.now().millisecondsSinceEpoch;

      // Debounce 160ms between individual shake swings
      if (nowMs - lastPeakTimestampMs < 160) return;
      lastPeakTimestampMs = nowMs;

      // Reset counter if more than 2.2 seconds passed since first shake
      if (nowMs - firstShakeTimestampMs > 2200) {
        shakePeakCount = 0;
        firstShakeTimestampMs = nowMs;
      }

      shakePeakCount++;

      // Trigger SOS only when 3 firm shakes occur within 2.2 seconds!
      if (shakePeakCount >= 3) {
        shakePeakCount = 0;
        isCooldown = true;
        uiHandledSOS = false;
        service.invoke('fallDetected');

        Future.delayed(const Duration(seconds: 2), () async {
          if (!uiHandledSOS) {
            await _triggerBackgroundEmergency("🚨 FALL / PANIC SHAKE DETECTED! I need immediate help.");
          }
        });

        Future.delayed(const Duration(seconds: 20), () => isCooldown = false);
      }
    }
  });

  // 4. PERSISTENT ESCORT TIMER & LOCATION WATCHDOG
  service.on('startEscortMode').listen((event) async {
    int minutes = event?['minutes'] ?? 1;
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    DateTime targetTime = DateTime.now().add(Duration(minutes: minutes));
    await prefs.setString('escort_end_time', targetTime.toIso8601String());
  });

  service.on('cancelEscortMode').listen((event) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    await prefs.remove('escort_end_time');
  });

  int tickCount = 0;
  Timer.periodic(const Duration(seconds: 2), (timer) async {
    tickCount++;
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    if (prefs.getBool('stop_alarm_flag') == true && isBgAlarmRinging) {
      await forceStopBgAlarm();
    }

    String? currentPhone = prefs.getString('user_phone')?.trim();
    if (currentPhone != null && currentPhone.isNotEmpty) {
      _bindFirestoreListeners(currentPhone);

      if (tickCount % 3 == 0) {
        for (String vPhone in getPhoneVariants(currentPhone)) {
          try {
            var doc = await FirebaseFirestore.instance
                .collection('location_requests')
                .doc(vPhone)
                .get()
                .timeout(const Duration(seconds: 3));
            if (doc.exists && doc.data()?['status'] == 'pending') {
              await fulfillLocationRequestEverywhere(vPhone);
            }
          } catch (_) {}
        }
      }

      if (tickCount % 15 == 0) {
        try {
          Position? p = await Geolocator.getLastKnownPosition()
              .timeout(const Duration(seconds: 2), onTimeout: () => null);
          if (p != null) {
            await prefs.setDouble('last_lat', p.latitude);
            await prefs.setDouble('last_long', p.longitude);
          }
        } catch (_) {}
      }
    }

    String? endTimeStr = prefs.getString('escort_end_time');
    if (endTimeStr != null) {
      DateTime endTime = DateTime.parse(endTimeStr);
      if (DateTime.now().isAfter(endTime)) {
        await prefs.remove('escort_end_time');
        service.invoke('fallDetected');
        await _triggerBackgroundEmergency("🚨 ESCORT MODE TIMER EXPIRED! I need immediate help.");
      }
    }
  });

  service.on('stopService').listen((event) => service.stopSelf());
}

// 🔥 NON-BLOCKING 4-LAYER LOCATION FULFILLER (Strict 3s Timeout)
Future<void> fulfillLocationRequestEverywhere(String targetDocPhone) async {
  try {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      ).timeout(const Duration(seconds: 3), onTimeout: () => throw TimeoutException('GPS timeout'));
    } catch (_) {
      try {
        pos = await Geolocator.getLastKnownPosition()
            .timeout(const Duration(seconds: 2), onTimeout: () => null);
      } catch (_) {}
    }

    double lat = pos?.latitude ?? prefs.getDouble('last_lat') ?? 30.1575;
    double long = pos?.longitude ?? prefs.getDouble('last_long') ?? 71.5249;

    await prefs.setDouble('last_lat', lat);
    await prefs.setDouble('last_long', long);

    for (String vPhone in getPhoneVariants(targetDocPhone)) {
      try {
        await FirebaseFirestore.instance.collection('location_requests').doc(vPhone).set({
          'status': 'fulfilled',
          'lat': lat,
          'long': long,
          'timestamp': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true)).timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
  } catch (e) {}
}

// 🔥 NON-BLOCKING BACKGROUND EMERGENCY DISPATCHER
Future<void> _triggerBackgroundEmergency(String prefixMsg) async {
  try {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    String? myPhone = prefs.getString('user_phone')?.trim();
    if (myPhone == null || myPhone.isEmpty) return;

    Position? position;
    try {
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      ).timeout(const Duration(seconds: 3), onTimeout: () => throw TimeoutException('GPS timeout'));
    } catch (_) {
      try {
        position = await Geolocator.getLastKnownPosition()
            .timeout(const Duration(seconds: 2), onTimeout: () => null);
      } catch (_) {}
    }

    double lat = position?.latitude ?? prefs.getDouble('last_lat') ?? 30.1575;
    double long = position?.longitude ?? prefs.getDouble('last_long') ?? 71.5249;

    String mapUrl = "https://maps.google.com/?q=$lat,$long";
    String message = "$prefixMsg Location: $mapUrl";

    List contacts = [];
    for (String myVar in getPhoneVariants(myPhone)) {
      try {
        var userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(myVar)
            .get()
            .timeout(const Duration(seconds: 3));
        if (userDoc.exists && userDoc.data()?['emergency_contacts'] != null) {
          contacts = userDoc.data()!['emergency_contacts'];
          break;
        }
      } catch (_) {}
    }

    for (var contact in contacts) {
      String contactPhone = contact['phone'].toString().trim();
      for (String cVar in getPhoneVariants(contactPhone)) {
        try {
          await FirebaseFirestore.instance.collection('active_alerts').doc(cVar).set({
            'from': myPhone,
            'message': message,
            'lat': lat,
            'long': long,
            'status': 'active',
            'timestamp': FieldValue.serverTimestamp(),
          }).timeout(const Duration(seconds: 3));
        } catch (_) {}

        try {
          var contactUserDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(cVar)
              .get()
              .timeout(const Duration(seconds: 3));
          if (contactUserDoc.exists && contactUserDoc.data()!.containsKey('fcmToken')) {
            await FCMService.sendPushNotification(
              targetFCMToken: contactUserDoc.data()!['fcmToken'],
              senderPhone: myPhone,
              message: message,
            ).timeout(const Duration(seconds: 5));
          }
        } catch (e) {}
      }
    }
  } catch (e) {}
}