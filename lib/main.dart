import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nearby_connections/nearby_connections.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'fcm_service.dart';
import 'background_service.dart';
import 'login_screen.dart';
import 'contacts_screen.dart';
import 'settings_screen.dart';
import 'guide_screen.dart';

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);
final ValueNotifier<Color> colorNotifier = ValueNotifier(const Color(0xFFE53935));

// 🔒 Global 30-Second Silence Lock so alarm never restarts after pressing Mute/Acknowledge
int _silencedUntilMs = 0;

// 🔥 MASTER CROSS-ISOLATE ALARM & STROBE KILLER
Future<void> stopAllAlarms() async {
  _silencedUntilMs = DateTime.now().millisecondsSinceEpoch + 30000;
  try {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('stop_alarm_flag', true);
  } catch (_) {}

  try {
    await FlutterRingtonePlayer().stop();
  } catch (_) {}

  try {
    FlutterBackgroundService().invoke('stopAlarm');
  } catch (_) {}

  try {
    const platform = MethodChannel('com.safetyapp/native_sms');
    await platform
        .invokeMethod('toggleStrobe', {'enable': false})
        .timeout(const Duration(seconds: 2), onTimeout: () => null);
  } catch (_) {}
}

// 🚀 KILLED-STATE & BACKGROUND FCM HANDLER
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  const platform = MethodChannel('com.safetyapp/native_sms');

  String msgType = message.data['type']?.toString() ?? message.data['action']?.toString() ?? '';
  String sender = message.data['sender']?.toString() ?? 'Emergency Contact';
  String body = message.data['body']?.toString() ?? message.data['message']?.toString() ?? 'Tap to open Safety App Pro';

  // 1. SILENT LOCATION PING
  if (msgType == 'location_request') {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    String? myPhone = prefs.getString('user_phone')?.trim();
    if (myPhone != null && myPhone.isNotEmpty) {
      await fulfillLocationRequestEverywhere(myPhone);
    }
    return;
  }

  // 2. 💬 CHAT MESSAGE / VOICE NOTE / CAMERA PHOTO
  if (msgType == 'chat_message') {
    FlutterRingtonePlayer().playNotification();
    try {
      await platform.invokeMethod('showHeadsUpNotification', {
        'title': '💬 New Message from $sender',
        'body': body,
      });
    } catch (_) {}
    return;
  }

  // 3. 📞 INCOMING IN-APP VOICE CALL
  if (msgType == 'incoming_call') {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('stop_alarm_flag', false);
    FlutterRingtonePlayer().playRingtone(looping: true);
    try {
      await platform.invokeMethod('showHeadsUpNotification', {
        'title': '📞 Incoming Voice Call from $sender',
        'body': 'Tap here immediately to answer In-App Live Call!',
      });
    } catch (_) {}

    for (int i = 0; i < 24; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      await prefs.reload();
      if (prefs.getBool('stop_alarm_flag') == true) {
        await FlutterRingtonePlayer().stop();
        break;
      }
    }
    await FlutterRingtonePlayer().stop();
    return;
  }

  // 4. 🚨 EMERGENCY SOS ALARM + DIRECT SCREEN POPUP
  try {
    await platform.invokeMethod('showHeadsUpNotification', {
      'title': '🚨 EMERGENCY SOS FROM $sender!',
      'body': body,
    });
  } catch (_) {}

  SharedPreferences prefs = await SharedPreferences.getInstance();
  await prefs.setBool('stop_alarm_flag', false);
  FlutterRingtonePlayer().playAlarm(volume: 1.0, looping: true, asAlarm: true);

  for (int i = 0; i < 30; i++) {
    await Future.delayed(const Duration(milliseconds: 500));
    await prefs.reload();
    if (prefs.getBool('stop_alarm_flag') == true) {
      await FlutterRingtonePlayer().stop();
      break;
    }
  }
  await FlutterRingtonePlayer().stop();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await requestPermissions();
  await initializeBackgroundService();

  SharedPreferences prefs = await SharedPreferences.getInstance();
  String? savedPhone = prefs.getString('user_phone');

  bool isDark = prefs.getBool('isDark') ?? false;
  themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
  int? colorInt = prefs.getInt('themeColor');
  if (colorInt != null) colorNotifier.value = Color(colorInt);

  runApp(SafetyAppPro(isLoggedIn: savedPhone != null && savedPhone.trim().isNotEmpty));
}

Future<void> requestPermissions() async {
  await [
    Permission.location,
    Permission.locationAlways,
    Permission.camera,
    Permission.microphone,
    Permission.bluetooth,
    Permission.bluetoothAdvertise,
    Permission.bluetoothConnect,
    Permission.bluetoothScan,
    Permission.nearbyWifiDevices,
    Permission.sms,
    Permission.notification,
  ].request();
}

class SafetyAppPro extends StatelessWidget {
  final bool isLoggedIn;
  const SafetyAppPro({super.key, required this.isLoggedIn});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Color>(
      valueListenable: colorNotifier,
      builder: (_, Color currentColor, __) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: themeNotifier,
          builder: (_, ThemeMode currentMode, __) {
            return MaterialApp(
              debugShowCheckedModeBanner: false,
              themeMode: currentMode,
              theme: ThemeData(
                colorScheme: ColorScheme.fromSeed(seedColor: currentColor, brightness: Brightness.light),
                appBarTheme: AppBarTheme(backgroundColor: currentColor, foregroundColor: Colors.white),
              ),
              darkTheme: ThemeData(
                colorScheme: ColorScheme.fromSeed(seedColor: currentColor, brightness: Brightness.dark),
                appBarTheme: AppBarTheme(backgroundColor: currentColor, foregroundColor: Colors.white),
              ),
              home: SplashScreen(isLoggedIn: isLoggedIn),
            );
          },
        );
      },
    );
  }
}

class SplashScreen extends StatefulWidget {
  final bool isLoggedIn;
  const SplashScreen({super.key, required this.isLoggedIn});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _mainController;
  late AnimationController _pulseController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _mainController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..repeat(reverse: true);

    _scaleAnimation = CurvedAnimation(parent: _mainController, curve: Curves.easeOutBack);
    _fadeAnimation = CurvedAnimation(parent: _mainController, curve: Curves.easeIn);
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.8), end: Offset.zero).animate(
      CurvedAnimation(parent: _mainController, curve: Curves.easeOutCubic),
    );

    _mainController.forward();

    Future.delayed(const Duration(milliseconds: 3800), () {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 600),
          pageBuilder: (_, __, ___) => widget.isLoggedIn ? const MainScreen() : const LoginScreen(),
          transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
        ),
      );
    });
  }

  @override
  void dispose() {
    _mainController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Color primaryColor = Theme.of(context).colorScheme.primary;
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [primaryColor.withOpacity(0.95), const Color(0xFF8E0000), const Color(0xFF1A0000)],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(height: 40),
              ScaleTransition(
                scale: _scaleAnimation,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) {
                            return Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(0.1),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.white.withOpacity(0.15 + (_pulseController.value * 0.25)),
                                    blurRadius: 30 + (_pulseController.value * 25),
                                    spreadRadius: 5 + (_pulseController.value * 12),
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.security_rounded, size: 95, color: Colors.white),
                            );
                          },
                        ),
                        const SizedBox(height: 28),
                        const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text("SAFETY APP PRO", style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 3.0)),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text("AI-GRADE FALL & EMERGENCY RESPONSE SYSTEM", style: TextStyle(fontSize: 11, color: Colors.white70, letterSpacing: 1.2, fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(height: 40),
                        const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(color: Colors.amberAccent, strokeWidth: 2.5)),
                      ],
                    ),
                  ),
                ),
              ),
              SlideTransition(
                position: _slideAnimation,
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 35.0, left: 24, right: 24),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [Colors.white.withOpacity(0.12), Colors.white.withOpacity(0.05)]),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.amberAccent.withOpacity(0.6), width: 1.5),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: const [
                          Text("DESIGNED & DEVELOPED BY", style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.amberAccent, letterSpacing: 2.2)),
                          SizedBox(height: 6),
                          Text("M Humza Arshad", style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1.2)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});
  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  String statusMessage = "System Ready - Monitoring Active";
  final Nearby nearby = Nearby();
  String? myPhoneNumber;
  bool _isDialogShowing = false;
  bool _isCallDialogShowing = false;
  bool _isGpsBusy = false;
  Position? _cachedPosition;

  final List<StreamSubscription> _allSubscriptions = [];
  static const platform = MethodChannel('com.safetyapp/native_sms');
  int _selectedEscortMinutes = 1;

  Timer? _batteryWatchdogTimer;
  int _currentBatteryLevel = 100;
  bool _lastBreathSent = false;
  bool _lowBatteryProtectionEnabled = true;

  bool _autoWhatsAppOnSOS = false;
  bool _isSafeZoneActive = false;
  double? _safeZoneLat;
  double? _safeZoneLong;
  Timer? _safeZoneTimer;
  final double _safeZoneRadiusMeters = 150.0;

  bool _isStrobeActive = false;
  bool _isBreadcrumbActive = false;
  Timer? _breadcrumbTimer;
  String _liveTelemetryText = "Speed: 0.0 km/h • Trail Idle";
  int _breadcrumbCount = 0;

  @override
  void initState() {
    super.initState();
    _initSystem();

    Future.delayed(const Duration(seconds: 8), () {
      if (mounted) _startBatteryWatchdog();
    });

    Future.delayed(const Duration(seconds: 2), () {
      _enforceBatteryPermissions();
    });

    FlutterBackgroundService().on('fallDetected').listen((event) {
      FlutterBackgroundService().invoke('uiHandledSOS');
      if (mounted) _triggerSOS();
    });

    FlutterBackgroundService().on('showSOSDialog').listen((data) {
      if (mounted && data != null) {
        _showIncomingAlertDialog(Map<String, dynamic>.from(data as Map));
      }
    });

    FlutterBackgroundService().on('incomingCall').listen((data) {
      if (mounted && data != null) {
        _showIncomingCallDialog(Map<String, dynamic>.from(data as Map));
      }
    });
  }

  Future<Map<String, double>> _getFastPositionSafe() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    double fallbackLat = _cachedPosition?.latitude ?? prefs.getDouble('last_lat') ?? 30.1575;
    double fallbackLong = _cachedPosition?.longitude ?? prefs.getDouble('last_long') ?? 71.5249;
    double fallbackSpeed = _cachedPosition?.speed ?? 0.0;

    if (_isGpsBusy) {
      return {'lat': fallbackLat, 'long': fallbackLong, 'speed': fallbackSpeed};
    }

    _isGpsBusy = true;
    Position? pos;

    try {
      pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      ).timeout(const Duration(seconds: 3), onTimeout: () => throw TimeoutException('GPS timeout'));
    } catch (_) {
      try {
        pos = await Geolocator.getLastKnownPosition().timeout(const Duration(seconds: 2), onTimeout: () => null);
      } catch (_) {}
    } finally {
      _isGpsBusy = false;
    }

    if (pos != null) {
      _cachedPosition = pos;
      await prefs.setDouble('last_lat', pos.latitude);
      await prefs.setDouble('last_long', pos.longitude);
      return {
        'lat': pos.latitude,
        'long': pos.longitude,
        'speed': pos.speed < 0 ? 0.0 : pos.speed,
      };
    }

    return {'lat': fallbackLat, 'long': fallbackLong, 'speed': fallbackSpeed};
  }

  Future<void> _showLocalScreenNotification(String title, String body) async {
    try {
      await platform.invokeMethod('showHeadsUpNotification', {
        'title': title,
        'body': body,
      }).timeout(const Duration(seconds: 2), onTimeout: () => null);
    } catch (_) {}
  }

  Future<void> _toggleFlashlightStrobe({bool? forceState}) async {
    bool targetState = forceState ?? !_isStrobeActive;
    try {
      await platform.invokeMethod('toggleStrobe', {'enable': targetState}).timeout(const Duration(seconds: 2), onTimeout: () => null);
      if (mounted) setState(() => _isStrobeActive = targetState);
    } catch (e) {}
  }

  void _toggleBreadcrumbTracking({bool? forceStart, bool delayFirstPoint = false}) {
    bool shouldActivate = forceStart ?? !_isBreadcrumbActive;
    if (!shouldActivate) {
      _breadcrumbTimer?.cancel();
      setState(() {
        _isBreadcrumbActive = false;
        _liveTelemetryText = "Speed: 0.0 km/h • Trail Stopped";
      });
      return;
    }

    setState(() {
      _isBreadcrumbActive = true;
      _breadcrumbCount = 0;
      _liveTelemetryText = "Live Trail Active (Updating every 20s)...";
    });

    if (!delayFirstPoint) {
      _pushBreadcrumbPoint();
    }
    _breadcrumbTimer?.cancel();
    _breadcrumbTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      _pushBreadcrumbPoint();
    });
  }

  Future<void> _pushBreadcrumbPoint() async {
    if (!_isBreadcrumbActive || myPhoneNumber == null) return;
    try {
      var coords = await _getFastPositionSafe();
      double lat = coords['lat']!;
      double long = coords['long']!;
      double speedKmh = coords['speed']! * 3.6;
      _breadcrumbCount++;

      if (mounted) {
        setState(() {
          _liveTelemetryText = "Pt #$_breadcrumbCount • ${speedKmh.toStringAsFixed(1)} km/h • (${lat.toStringAsFixed(3)}, ${long.toStringAsFixed(3)})";
        });
      }

      List contacts = await _getSavedContactsSafe();
      for (var c in contacts) {
        String cPhone = c['phone'].toString().trim();
        for (String cVar in getPhoneVariants(cPhone)) {
          await FirebaseFirestore.instance.collection('active_alerts').doc(cVar).set({
            'from': myPhoneNumber,
            'lat': lat,
            'long': long,
            'speed_kmh': speedKmh.toStringAsFixed(1),
            'message': "🛰️ LIVE TRAIL UPDATE #$_breadcrumbCount (Speed: ${speedKmh.toStringAsFixed(1)} km/h)\nhttps://maps.google.com/?q=$lat,$long",
            'status': 'active',
            'timestamp': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true)).timeout(const Duration(seconds: 4), onTimeout: () => null);
        }
      }
    } catch (e) {}
  }

  Future<void> _dialEmergencyNumber(String number, String title) async {
    final Uri telUri = Uri.parse("tel:$number");
    try {
      await launchUrl(telUri, mode: LaunchMode.externalApplication);
    } catch (e) {}
  }

  void _triggerFakePoliceCall() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('🚔 Fake Police Call scheduled in 5 seconds...'), backgroundColor: Colors.blueGrey, duration: Duration(seconds: 3)),
    );

    Future.delayed(const Duration(seconds: 5), () {
      if (!mounted) return;
      FlutterRingtonePlayer().playRingtone(looping: true);
      _showLocalScreenNotification("🚔 Police Control Room (15)", "Incoming Emergency Verification Call...");
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF121B22),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Column(
            children: const [
              CircleAvatar(radius: 36, backgroundColor: Colors.redAccent, child: Icon(Icons.local_police_rounded, size: 42, color: Colors.white)),
              SizedBox(height: 12),
              Text("Police Control Room (15)", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20)),
              SizedBox(height: 4),
              Text("Incoming Emergency Verification Call...", style: TextStyle(color: Colors.white70, fontSize: 13)),
            ],
          ),
          actionsAlignment: MainAxisAlignment.spaceEvenly,
          actions: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () async {
                await stopAllAlarms();
                if (Navigator.canPop(ctx)) Navigator.pop(ctx);
              },
              icon: const Icon(Icons.call_end),
              label: const Text("Decline"),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
              onPressed: () async {
                await stopAllAlarms();
                if (Navigator.canPop(ctx)) Navigator.pop(ctx);
                _showActiveFakeCallScreen();
              },
              icon: const Icon(Icons.call),
              label: const Text("Answer"),
            ),
          ],
        ),
      );
    });
  }

  void _showActiveFakeCallScreen() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF075E54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("🚔 Connected: Police 15 Dispatch", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
        content: const Text("🔊 Live GPS Patrol Tracking Active.\nSpeak normally so anyone nearby knows Police Control Room has your live location.", style: TextStyle(color: Colors.white70, fontSize: 14)),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.call_end),
              label: const Text("END CALL"),
            ),
          ),
        ],
      ),
    );
  }

  void _showIncomingCallDialog(Map<String, dynamic> callData) {
    if (DateTime.now().millisecondsSinceEpoch < _silencedUntilMs) return;
    if (_isCallDialogShowing) return;
    _isCallDialogShowing = true;
    String callerPhone = callData['callerName']?.toString() ?? callData['caller']?.toString() ?? 'Emergency Contact';

    FlutterRingtonePlayer().playRingtone(looping: true);
    _showLocalScreenNotification("📞 Incoming Call: $callerPhone", "Tap to answer In-App Live Voice Call");

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF121B22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          children: [
            const CircleAvatar(radius: 35, backgroundColor: Color(0xFF075E54), child: Icon(Icons.phone_in_talk_rounded, size: 38, color: Colors.white)),
            const SizedBox(height: 12),
            Text("Incoming Call: $callerPhone", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 6),
            const Text("Safety App Pro • In-App Live Voice Channel", style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
          ],
        ),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              await stopAllAlarms();
              if (Navigator.canPop(ctx)) Navigator.pop(ctx);
              if (myPhoneNumber != null) {
                for (String vPhone in getPhoneVariants(myPhoneNumber!)) {
                  try {
                    await FirebaseFirestore.instance.collection('active_calls').doc(vPhone).set({'status': 'ended'}, SetOptions(merge: true));
                  } catch (_) {}
                }
              }
              _isCallDialogShowing = false;
            },
            icon: const Icon(Icons.call_end),
            label: const Text("Decline"),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () async {
              await stopAllAlarms();
              if (Navigator.canPop(ctx)) Navigator.pop(ctx);
              if (myPhoneNumber != null) {
                for (String vPhone in getPhoneVariants(myPhoneNumber!)) {
                  try {
                    await FirebaseFirestore.instance.collection('active_calls').doc(vPhone).set({'status': 'connected'}, SetOptions(merge: true));
                  } catch (_) {}
                }
              }
              _isCallDialogShowing = false;
              if (mounted && myPhoneNumber != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LiveChatScreen(
                      myPhone: myPhoneNumber!,
                      targetPhone: callerPhone,
                      targetName: callerPhone,
                    ),
                  ),
                );
              }
            },
            icon: const Icon(Icons.call),
            label: const Text("Accept & Talk"),
          ),
        ],
      ),
    );
  }

  Future<void> _openEmergencyLiveChat() async {
    List contacts = await _getSavedContactsSafe();
    if (contacts.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Add an Emergency Contact first to start Live Chat!'), backgroundColor: Colors.red),
      );
      Navigator.push(context, MaterialPageRoute(builder: (_) => const ContactsScreen()));
      return;
    }

    if (contacts.length == 1) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LiveChatScreen(
            myPhone: myPhoneNumber ?? '',
            targetPhone: contacts[0]['phone'].toString(),
            targetName: contacts[0]['name'].toString(),
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("💬 Select Contact for Live Chat & Voice", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: contacts
                      .map((c) => ListTile(
                            leading: const CircleAvatar(backgroundColor: Color(0xFF075E54), child: Icon(Icons.chat, color: Colors.white)),
                            title: Text(c['name'].toString(), style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(c['phone'].toString()),
                            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                            onTap: () {
                              Navigator.pop(ctx);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => LiveChatScreen(
                                    myPhone: myPhoneNumber ?? '',
                                    targetPhone: c['phone'].toString(),
                                    targetName: c['name'].toString(),
                                  ),
                                ),
                              );
                            },
                          ))
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _startBatteryWatchdog() {
    _checkBatteryAndTriggerLastBreath();
    _batteryWatchdogTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      _checkBatteryAndTriggerLastBreath();
    });
  }

  Future<void> _checkBatteryAndTriggerLastBreath() async {
    try {
      final int? level = await platform.invokeMethod<int>('getBatteryLevel').timeout(const Duration(seconds: 2), onTimeout: () => null);
      if (level != null && level > 0) {
        if (mounted) setState(() { _currentBatteryLevel = level; });
        if (level > 15) _lastBreathSent = false;

        if (_lowBatteryProtectionEnabled && level <= 10 && !_lastBreathSent) {
          _lastBreathSent = true;
          await _triggerCustomSOS("LAST BREATH BATTERY ALERT! My phone battery is critically low ($level%) and about to switch off.");
        }
      }
    } catch (e) {}

    try {
      var coords = await _getFastPositionSafe();
      if (myPhoneNumber != null) {
        for (String myVar in getPhoneVariants(myPhoneNumber!)) {
          await FirebaseFirestore.instance.collection('users').doc(myVar).set({
            'lastLat': coords['lat'],
            'lastLong': coords['long'],
            'lastUpdated': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true)).timeout(const Duration(seconds: 3), onTimeout: () => null);
        }
      }
    } catch (_) {}
  }

  void _toggleSafeZone() async {
    if (_isSafeZoneActive) {
      _safeZoneTimer?.cancel();
      setState(() {
        _isSafeZoneActive = false;
        _safeZoneLat = null;
        _safeZoneLong = null;
        statusMessage = "Safe-Zone Deactivated.";
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🔓 Safe-Zone Boundary Unlocked.'), backgroundColor: Colors.grey));
      return;
    }

    setState(() => statusMessage = "LOCKING SAFE-ZONE (150m)...");
    var coords = await _getFastPositionSafe();
    _safeZoneLat = coords['lat'];
    _safeZoneLong = coords['long'];

    setState(() {
      _isSafeZoneActive = true;
      statusMessage = "🛡️ Safe-Zone Locked (150m Radius)";
    });

    await _showLocalScreenNotification("🛡️ Safe-Zone Locked (150m)", "Auto-SOS will trigger if you move outside 150m.");
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🛡️ Safe-Zone Active! Auto-SOS will fire if you leave a 150m radius.'), backgroundColor: Colors.teal),
      );
    }

    _safeZoneTimer?.cancel();
    _safeZoneTimer = Timer.periodic(const Duration(seconds: 12), (timer) async {
      if (!_isSafeZoneActive || _safeZoneLat == null || _safeZoneLong == null) return;
      try {
        var nowCoords = await _getFastPositionSafe();
        double distance = Geolocator.distanceBetween(
          _safeZoneLat!,
          _safeZoneLong!,
          nowCoords['lat']!,
          nowCoords['long']!,
        );

        if (distance > _safeZoneRadiusMeters) {
          timer.cancel();
          if (mounted) {
            setState(() {
              _isSafeZoneActive = false;
              statusMessage = "🚨 SAFE-ZONE BREACHED! SENDING SOS...";
            });
          }
          await _triggerCustomSOS("SAFE-ZONE BREACH ALERT! I have moved ${distance.toInt()}m outside my locked safety boundary!");
        }
      } catch (e) {}
    });
  }

  void _enforceBatteryPermissions() async {
    if (await Permission.ignoreBatteryOptimizations.isDenied) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text("⚠️ CRITICAL SAFETY SETUP", style: TextStyle(color: Colors.red)),
          content: const Text("To save your life in an emergency, this app needs to monitor falls and run Escort Mode even when your phone is locked.\n\nPlease select 'Allow' or 'Unrestricted'."),
          actions: [
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await Permission.ignoreBatteryOptimizations.request();
              },
              child: const Text("CONTINUE"),
            )
          ],
        ),
      );
    }
  }

  void _initSystem() async {
    await stopAllAlarms();

    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      String msgType = message.data['type']?.toString() ?? message.data['action']?.toString() ?? '';
      String sender = message.data['sender']?.toString() ?? 'Contact';
      String body = message.data['body']?.toString() ?? message.data['message']?.toString() ?? 'New Alert';

      if (msgType == 'chat_message') {
        FlutterRingtonePlayer().playNotification();
        await _showLocalScreenNotification('💬 Message from $sender', body);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF075E54),
              duration: const Duration(seconds: 5),
              content: Text('💬 $sender: $body', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              action: SnackBarAction(
                label: 'OPEN CHAT',
                textColor: Colors.amberAccent,
                onPressed: () {
                  if (myPhoneNumber != null && myPhoneNumber!.isNotEmpty) {
                    Navigator.push(context, MaterialPageRoute(builder: (_) => LiveChatScreen(myPhone: myPhoneNumber!, targetPhone: sender, targetName: sender)));
                  }
                },
              ),
            ),
          );
        }
      } else if (msgType == 'incoming_call') {
        _showIncomingCallDialog({'callerName': sender, 'caller': sender});
      } else if (msgType == 'sos_alert') {
        await _showLocalScreenNotification('🚨 EMERGENCY SOS FROM $sender!', body);
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      stopAllAlarms();
      String msgType = message.data['type']?.toString() ?? message.data['action']?.toString() ?? '';
      String sender = message.data['sender']?.toString() ?? '';
      if ((msgType == 'chat_message' || msgType == 'incoming_call') && mounted && myPhoneNumber != null && sender.isNotEmpty) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => LiveChatScreen(myPhone: myPhoneNumber!, targetPhone: sender, targetName: sender)));
      }
    });

    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    setState(() {
      myPhoneNumber = prefs.getString('user_phone')?.trim();
    });

    if (myPhoneNumber != null && myPhoneNumber!.isNotEmpty) {
      for (var s in _allSubscriptions) {
        s.cancel();
      }
      _allSubscriptions.clear();

      _listenForIncomingAlertsLocationsAndCalls();
      await requestPermissions();
      _startMeshDiscovery();

      FirebaseMessaging messaging = FirebaseMessaging.instance;
      NotificationSettings settings = await messaging.requestPermission(alert: true, badge: true, sound: true);
      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        String? fcmToken = await messaging.getToken();
        if (fcmToken != null) {
          for (String myVar in getPhoneVariants(myPhoneNumber!)) {
            try {
              await FirebaseFirestore.instance.collection('users').doc(myVar).set(
                {'fcmToken': fcmToken, 'lastUpdated': FieldValue.serverTimestamp()},
                SetOptions(merge: true),
              );
            } catch (e) {}
          }
        }
      }
    }
  }

  void _listenForIncomingAlertsLocationsAndCalls() {
    if (myPhoneNumber == null) return;
    for (String vPhone in getPhoneVariants(myPhoneNumber!)) {
      var locSub = FirebaseFirestore.instance.collection('location_requests').doc(vPhone).snapshots().listen((snapshot) async {
        if (snapshot.exists && snapshot.data() != null) {
          var data = snapshot.data() as Map<String, dynamic>;
          if (data['status'] == 'pending') {
            await fulfillLocationRequestEverywhere(vPhone);
          }
        }
      });
      _allSubscriptions.add(locSub);

      var alertSub = FirebaseFirestore.instance.collection('active_alerts').doc(vPhone).snapshots().listen((snapshot) {
        if (snapshot.exists && snapshot.data() != null) {
          var data = snapshot.data() as Map<String, dynamic>;
          if (data['status'] == 'active') {
            _showIncomingAlertDialog(data);
          }
        }
      });
      _allSubscriptions.add(alertSub);

      var callSub = FirebaseFirestore.instance.collection('active_calls').doc(vPhone).snapshots().listen((snapshot) {
        if (snapshot.exists && snapshot.data() != null) {
          var data = snapshot.data() as Map<String, dynamic>;
          if (data['status'] == 'ringing') {
            _showIncomingCallDialog(data);
          }
        }
      });
      _allSubscriptions.add(callSub);
    }
  }

  void _startMeshDiscovery() async {
    try {
      await nearby.stopAllEndpoints();
      await nearby.stopAdvertising();
      await nearby.stopDiscovery();

      await nearby.startDiscovery(
        "Rescuer",
        Strategy.P2P_CLUSTER,
        serviceId: "com.safetyapp.mesh",
        onEndpointFound: (id, name, endpointInfo) {
          if (name.startsWith("SOS_")) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('📡 Offline Radar: SOS Signal Detected! Connecting...'), backgroundColor: Colors.blue));
            }
            nearby.requestConnection(
              "Rescuer",
              id,
              onConnectionInitiated: (id, info) {
                nearby.acceptConnection(
                  id,
                  onPayLoadRecieved: (endId, payload) async {
                    if (payload.bytes != null) {
                      String msg = utf8.decode(payload.bytes!);
                      if (mounted) {
                        _showIncomingAlertDialog({"from": name.replaceAll("SOS_", ""), "message": msg});
                      }
                      await nearby.stopAllEndpoints();
                      _startMeshDiscovery();
                    }
                  },
                );
              },
              onConnectionResult: (id, status) {
                if (status != Status.CONNECTED) _startMeshDiscovery();
              },
              onDisconnected: (id) => _startMeshDiscovery(),
            );
          }
        },
        onEndpointLost: (id) {},
      );
    } catch (e) {}
  }

  void _startEscortMode() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    DateTime targetTime = DateTime.now().add(Duration(minutes: _selectedEscortMinutes));
    await prefs.setString('escort_end_time', targetTime.toIso8601String());
    FlutterBackgroundService().invoke('startEscortMode', {'minutes': _selectedEscortMinutes});

    await _showLocalScreenNotification("🛡️ Escort Mode Active", "Timer set for $_selectedEscortMinutes min(s). Auto-SOS will fire if not cancelled.");
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('🛡️ Escort Mode Activated for $_selectedEscortMinutes Minute(s)!'), backgroundColor: Colors.orange, duration: const Duration(seconds: 4)),
    );
  }

  void _cancelEscortModeWithPinTrap() {
    final TextEditingController pinController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("🔐 Enter Safety PIN to Cancel", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("• Normal Safe PIN: 1234\n• Hostage/Duress PIN: 9999 (Fake cancel + Silent SOS)", style: TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 10),
            TextField(
              controller: pinController,
              keyboardType: TextInputType.number,
              obscureText: true,
              maxLength: 4,
              decoration: const InputDecoration(labelText: "4-Digit Safety PIN", border: OutlineInputBorder(), prefixIcon: Icon(Icons.lock)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("BACK")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () async {
              String enteredPin = pinController.text.trim();
              Navigator.pop(ctx);

              SharedPreferences prefs = await SharedPreferences.getInstance();
              await prefs.remove('escort_end_time');
              FlutterBackgroundService().invoke('cancelEscortMode');

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('✅ Escort Mode Cancelled. You are safe.'), backgroundColor: Colors.green, duration: Duration(seconds: 3)),
                );
              }

              if (enteredPin != "1234") {
                await _triggerCustomSOS("HOSTAGE / DURESS PIN ALERT! Someone forced me to cancel Escort Mode under threat (PIN entered: $enteredPin)!");
              }
            },
            child: const Text("VERIFY & CANCEL"),
          ),
        ],
      ),
    );
  }

  // 🔥 BULLETPROOF INCOMING SOS DIALOG & INSTANT SILENCE HANDLER
  void _showIncomingAlertDialog(Map<String, dynamic> data) async {
    if (DateTime.now().millisecondsSinceEpoch < _silencedUntilMs) return;
    if (_isDialogShowing) return;
    _isDialogShowing = true;

    double? lat = (data['lat'] as num?)?.toDouble();
    double? long = (data['long'] as num?)?.toDouble();
    String senderMessage = data['message'] ?? 'Emergency triggered!';
    String senderFrom = data['from'] ?? 'Unknown Sender';

    await _showLocalScreenNotification("🚨 EMERGENCY SOS FROM $senderFrom!", senderMessage);

    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('stop_alarm_flag', false);
    try {
      await FlutterRingtonePlayer().stop();
      FlutterRingtonePlayer().playAlarm(volume: 1.0, looping: true, asAlarm: true);
    } catch (_) {}

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text("🚨 EMERGENCY ALERT!", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("From:\n$senderFrom", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),
            Text(senderMessage),
            const SizedBox(height: 10),
            if (lat != null && long != null)
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.grey.withOpacity(0.2),
                child: Text("📍 Lat: $lat\nLng: $long", style: const TextStyle(fontWeight: FontWeight.bold)),
              ),
          ],
        ),
        actions: [
          if (lat != null && long != null)
            TextButton.icon(
              onPressed: () async {
                final Uri mapUri = Uri.parse("https://www.google.com/maps/search/?api=1&query=$lat,$long");
                if (await canLaunchUrl(mapUri)) await launchUrl(mapUri, mode: LaunchMode.externalApplication);
              },
              icon: const Icon(Icons.map, color: Colors.blue),
              label: const Text("MAP"),
            ),
          ElevatedButton(
            onPressed: () async {
              await stopAllAlarms();
              if (Navigator.canPop(dialogContext)) Navigator.pop(dialogContext);
              if (myPhoneNumber != null) {
                for (String myVar in getPhoneVariants(myPhoneNumber!)) {
                  try {
                    await FirebaseFirestore.instance.collection('active_alerts').doc(myVar).delete();
                  } catch (e) {}
                }
              }
              _isDialogShowing = false;
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("ACKNOWLEDGE & SILENCE", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  Future<void> _sendWhatsAppAlert(List contactList, String message) async {
    if (contactList.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ Add at least 1 Emergency Contact first!'), backgroundColor: Colors.red),
        );
      }
      return;
    }
    String rawPhone = contactList[0]['phone'].toString().trim();
    String cleanWhatsappPhone = rawPhone.replaceAll(RegExp(r'[^0-9]'), '');
    if (cleanWhatsappPhone.startsWith('03')) {
      cleanWhatsappPhone = '92${cleanWhatsappPhone.substring(1)}';
    }

    final Uri whatsappAppUri = Uri.parse("whatsapp://send?phone=$cleanWhatsappPhone&text=${Uri.encodeComponent(message)}");
    final Uri whatsappWebUri = Uri.parse("https://wa.me/$cleanWhatsappPhone?text=${Uri.encodeComponent(message)}");

    try {
      bool launched = await launchUrl(whatsappAppUri, mode: LaunchMode.externalApplication);
      if (!launched) {
        await launchUrl(whatsappWebUri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      try {
        await launchUrl(whatsappWebUri, mode: LaunchMode.externalApplication);
      } catch (_) {}
    }
  }

  Future<void> _triggerDirectWhatsAppOnly() async {
    if (mounted) setState(() { statusMessage = "PREPARING WHATSAPP SOS..."; });
    var coords = await _getFastPositionSafe();
    double lat = coords['lat']!;
    double long = coords['long']!;
    String mapUrl = "https://maps.google.com/?q=$lat,$long";
    String waMessage = "🚨 *EMERGENCY SOS ALERT!*\nI need immediate help!\n\n📍 *My Live Location:*\n$mapUrl";

    List contactList = await _getSavedContactsSafe();
    await _sendWhatsAppAlert(contactList, waMessage);
    if (mounted) setState(() { statusMessage = "WHATSAPP SOS READY!"; });
  }

  Future<List> _getSavedContactsSafe() async {
    if (myPhoneNumber == null) return [];
    for (String myVar in getPhoneVariants(myPhoneNumber!)) {
      try {
        var contactsDoc = await FirebaseFirestore.instance.collection('users').doc(myVar).get().timeout(const Duration(seconds: 2));
        if (contactsDoc.exists && contactsDoc.data()?['emergency_contacts'] != null) {
          return contactsDoc.data()!['emergency_contacts'];
        }
      } catch (_) {
        try {
          var cachedDoc = await FirebaseFirestore.instance.collection('users').doc(myVar).get(const GetOptions(source: Source.cache));
          if (cachedDoc.exists && cachedDoc.data()?['emergency_contacts'] != null) {
            return cachedDoc.data()!['emergency_contacts'];
          }
        } catch (_) {}
      }
    }
    return [];
  }

  void _triggerSOS() {
    _toggleFlashlightStrobe(forceState: true);
    _toggleBreadcrumbTracking(forceStart: true, delayFirstPoint: true);
    _triggerCustomSOS("EMERGENCY SOS! I need help immediately.");
  }

  Future<void> _triggerCustomSOS(String customPrefix) async {
    if (mounted) setState(() { statusMessage = "FETCHING LOCATION & DISPATCHING SOS..."; });

    FlutterRingtonePlayer().playNotification();
    await _showLocalScreenNotification("🚨 SOS DISPATCHING...", customPrefix);

    var coords = await _getFastPositionSafe();
    double lat = coords['lat']!;
    double long = coords['long']!;

    String mapUrl = "https://maps.google.com/?q=$lat,$long";
    String smsCleanMessage = "$customPrefix Location: $mapUrl";
    String cloudRichMessage = "🚨 $customPrefix\n\n📍 Location:\n$mapUrl";

    List contactList = await _getSavedContactsSafe();
    if (contactList.isEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ No Emergency Contacts saved! Please add a contact in the Contacts screen.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 4),
        ),
      );
    }

    await _sendBackgroundSMS(contactList, smsCleanMessage);

    List<ConnectivityResult> connectivityResult = [];
    try {
      connectivityResult = await Connectivity().checkConnectivity().timeout(const Duration(seconds: 2));
    } catch (_) {}

    if (connectivityResult.contains(ConnectivityResult.none) || connectivityResult.isEmpty) {
      _startOfflineSOS(cloudRichMessage);
    } else {
      await _sendOnlineAlerts(contactList, cloudRichMessage, lat, long);
      if (_autoWhatsAppOnSOS && contactList.isNotEmpty) {
        await _sendWhatsAppAlert(contactList, cloudRichMessage);
      }
    }

    await _showLocalScreenNotification("✅ EMERGENCY ALERTS SENT!", "Location ($lat, $long) sent to ${contactList.length} contact(s).");
    if (mounted) {
      setState(() {
        statusMessage = "✅ ALERTS & SMS DISPATCHED (${contactList.length} CONTACTS)!";
      });
    }
  }

  Future<void> _sendBackgroundSMS(List contactList, String message) async {
    if (contactList.isEmpty) return;
    try {
      var status = await Permission.sms.status.timeout(const Duration(seconds: 2));
      if (!status.isGranted) {
        status = await Permission.sms.request().timeout(const Duration(seconds: 4));
      }
    } catch (_) {}

    int sentCount = 0;
    for (var contact in contactList) {
      String number = contact['phone'].toString().trim();
      try {
        await platform.invokeMethod('sendBackgroundSms', {
          'phone': number,
          'message': message,
        }).timeout(const Duration(seconds: 3));
        sentCount++;
      } catch (e) {}
    }

    if (mounted && sentCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('📩 Auto-SMS Dispatched to $sentCount Contact(s) via SIM!'), backgroundColor: Colors.green[800], duration: const Duration(seconds: 3)),
      );
    }
  }

  void _startOfflineSOS(String emergencyPayload) async {
    if (mounted) setState(() { statusMessage = "OFFLINE MODE: MESH BROADCASTING..."; });
    try {
      await nearby.stopAllEndpoints();
      await nearby.stopAdvertising();
      await nearby.stopDiscovery();

      await nearby.startAdvertising(
        "SOS_$myPhoneNumber",
        Strategy.P2P_CLUSTER,
        serviceId: "com.safetyapp.mesh",
        onConnectionInitiated: (id, info) {
          nearby.acceptConnection(id, onPayLoadRecieved: (endId, payload) {});
        },
        onConnectionResult: (id, status) {
          if (status == Status.CONNECTED) {
            nearby.sendBytesPayload(id, Uint8List.fromList(utf8.encode(emergencyPayload)));
            if (mounted) setState(() { statusMessage = "OFFLINE MESH ACTIVE! PAYLOAD SENT."; });
            Future.delayed(const Duration(seconds: 4), () async {
              await nearby.stopAllEndpoints();
              await nearby.stopAdvertising();
              if (mounted) setState(() { statusMessage = "TRANSMISSION COMPLETE."; });
              _startMeshDiscovery();
            });
          } else {
            _startMeshDiscovery();
          }
        },
        onDisconnected: (id) => _startMeshDiscovery(),
      );
    } catch (e) {
      _startMeshDiscovery();
    }
  }

  Future<void> _sendOnlineAlerts(List contactList, String message, double lat, double long) async {
    for (var contact in contactList) {
      String contactPhone = contact['phone'].toString().trim();
      for (String cVar in getPhoneVariants(contactPhone)) {
        try {
          await FirebaseFirestore.instance.collection('active_alerts').doc(cVar).set({
            'from': myPhoneNumber,
            'message': message,
            'lat': lat,
            'long': long,
            'status': 'active',
            'timestamp': FieldValue.serverTimestamp(),
          }).timeout(const Duration(seconds: 4));
        } catch (_) {}

        try {
          var userDoc = await FirebaseFirestore.instance.collection('users').doc(cVar).get().timeout(const Duration(seconds: 3));
          if (userDoc.exists && userDoc.data()!.containsKey('fcmToken')) {
            await FCMService.sendPushNotification(
              targetFCMToken: userDoc.data()!['fcmToken'],
              senderPhone: myPhoneNumber ?? 'Unknown',
              message: message,
            ).timeout(const Duration(seconds: 5));
          }
        } catch (e) {}
      }
    }
  }

  Widget _buildDetailedFeatureDrawer(Color primaryColor) {
    final List<Map<String, dynamic>> allFeaturesCatalog = [
      {
        'icon': Icons.sos_rounded,
        'color': Colors.red,
        'title': '1. Instant Multi-Channel SOS & Panic Shake',
        'detail': 'Purpose: Immediately dispatches live GPS via Background SIM SMS, Cloud FCM Siren, Strobe Light & Live Trail when tapped or shaken 3 times (>32.0).',
        'onTap': () { Navigator.pop(context); _triggerSOS(); },
      },
      {
        'icon': Icons.chat_rounded,
        'color': const Color(0xFF075E54),
        'title': '2. 2-Way Live Chat, Voice Notes & Camera',
        'detail': 'Purpose: WhatsApp-style emergency chat to send text, stoppable voice recordings, live camera photos, and GPS pins.',
        'onTap': () { Navigator.pop(context); _openEmergencyLiveChat(); },
      },
      {
        'icon': Icons.phone_in_talk_rounded,
        'color': Colors.green,
        'title': '3. In-App Live Voice Call (VoIP)',
        'detail': 'Purpose: Ring your emergency contact directly inside the app over internet even if you have zero SIM balance.',
        'onTap': () { Navigator.pop(context); _openEmergencyLiveChat(); },
      },
      {
        'icon': Icons.my_location_rounded,
        'color': Colors.blue,
        'title': '4. Remote Location Ping & Unlimited Contacts',
        'detail': 'Purpose: Remotely wake up a family member’s closed phone to fetch their live GPS coordinates without them touching their phone.',
        'onTap': () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const ContactsScreen())); },
      },
      {
        'icon': Icons.flashlight_on_rounded,
        'color': Colors.amber[800]!,
        'title': '5. Hardware Flashlight SOS Strobe',
        'detail': 'Purpose: Blinks the rear camera LED flash every 250ms as a visual rescue beacon in darkness.',
        'onTap': () { Navigator.pop(context); _toggleFlashlightStrobe(); },
      },
      {
        'icon': Icons.route_rounded,
        'color': Colors.deepPurple,
        'title': '6. Live Breadcrumb Trail & Vehicle Speed (20s)',
        'detail': 'Purpose: Continuously uploads moving GPS coordinates and vehicle speed (km/h) every 20 seconds to track kidnapping or travel routes.',
        'onTap': () { Navigator.pop(context); _toggleBreadcrumbTracking(); },
      },
      {
        'icon': Icons.timer_rounded,
        'color': Colors.orange,
        'title': '7. Dead-Man Switch (Escort Mode + PIN Trap)',
        'detail': 'Purpose: Countdown timer that fires SOS if you don’t reach safely. Protected by Safe PIN (1234) & Hostage Duress PIN (9999).',
        'onTap': () { Navigator.pop(context); _startEscortMode(); },
      },
      {
        'icon': Icons.security_rounded,
        'color': Colors.teal,
        'title': '8. Safe-Zone Geo-Fence Guard (150m Radius)',
        'detail': 'Purpose: Locks your current GPS position and triggers an automatic breach SOS if you move more than 150 meters outside the perimeter.',
        'onTap': () { Navigator.pop(context); _toggleSafeZone(); },
      },
      {
        'icon': Icons.battery_alert_rounded,
        'color': Colors.teal[800]!,
        'title': '9. Low-Battery "Last Breath" Auto-SOS (≤10%)',
        'detail': 'Purpose: Automatically transmits your final GPS location to family right before your phone battery dies.',
        'onTap': () { Navigator.pop(context); _triggerCustomSOS("LAST BREATH BATTERY ALERT! My phone battery is critically low ($_currentBatteryLevel%) and about to die."); },
      },
      {
        'icon': Icons.wifi_tethering_rounded,
        'color': Colors.purple,
        'title': '10. Offline P2P Mesh Network (Zero Net/SIM)',
        'detail': 'Purpose: Uses Bluetooth & Wi-Fi Direct to broadcast SOS alerts to nearby phones within 30m when internet and SIM signals fail.',
        'onTap': () { Navigator.pop(context); _startOfflineSOS("🚨 OFFLINE MESH SOS TEST! Need assistance nearby."); },
      },
      {
        'icon': Icons.local_police_rounded,
        'color': Colors.blueGrey,
        'title': '11. Fake Police Call Simulator (Police 15)',
        'detail': 'Purpose: Triggers a realistic incoming call from "Police Control Room (15)" after 5 seconds for psychological defense in suspicious rides.',
        'onTap': () { Navigator.pop(context); _triggerFakePoliceCall(); },
      },
      {
        'icon': Icons.send_rounded,
        'color': const Color(0xFF25D366),
        'title': '12. Direct WhatsApp SOS Dispatcher',
        'detail': 'Purpose: Immediately launches external WhatsApp with a pre-typed emergency message and live Google Maps pin.',
        'onTap': () { Navigator.pop(context); _triggerDirectWhatsAppOnly(); },
      },
    ];

    return Drawer(
      width: MediaQuery.of(context).size.width * 0.86,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.only(top: 45, bottom: 18, left: 16, right: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [primaryColor, const Color(0xFF1A0000)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.shield_rounded, color: Colors.amberAccent, size: 34),
                    SizedBox(width: 10),
                    Expanded(child: Text("Safety App Pro\nAll Features & Purpose", style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold))),
                  ],
                ),
                const SizedBox(height: 8),
                const Text("Tap any feature below to read its purpose & activate it directly • Developed by M Humza Arshad", style: TextStyle(color: Colors.white70, fontSize: 11.5)),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(10),
              itemCount: allFeaturesCatalog.length,
              separatorBuilder: (_, __) => const Divider(height: 10),
              itemBuilder: (context, index) {
                var f = allFeaturesCatalog[index];
                return Card(
                  elevation: 1.5,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    leading: CircleAvatar(backgroundColor: (f['color'] as Color).withOpacity(0.15), child: Icon(f['icon'] as IconData, color: f['color'] as Color)),
                    title: Text(f['title'], style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: f['color'] as Color)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4.0),
                      child: Text(f['detail'], style: const TextStyle(fontSize: 12, height: 1.35)),
                    ),
                    trailing: const Icon(Icons.play_circle_fill_rounded, color: Colors.grey, size: 22),
                    onTap: f['onTap'] as VoidCallback,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    for (var s in _allSubscriptions) {
      s.cancel();
    }
    _batteryWatchdogTimer?.cancel();
    _safeZoneTimer?.cancel();
    _breadcrumbTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Color primaryColor = Theme.of(context).colorScheme.primary;
    return Scaffold(
      drawer: _buildDetailedFeatureDrawer(primaryColor),
      appBar: AppBar(
        titleSpacing: 4,
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('Safety App Pro', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 19)),
        ),
        actions: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.chat_rounded, color: Colors.greenAccent),
            tooltip: 'Live Emergency Chat & Voice',
            onPressed: _openEmergencyLiveChat,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.help_outline),
            tooltip: 'Complete User Guide',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GuideScreen())),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.volume_off, color: Colors.yellowAccent),
            tooltip: 'Force Stop Alarm & Strobe',
            onPressed: () async {
              await stopAllAlarms();
              if (mounted) {
                setState(() {
                  _isStrobeActive = false;
                  statusMessage = "🔇 All Alarms & Strobe Silenced";
                });
              }
              if (myPhoneNumber != null) {
                for (String myVar in getPhoneVariants(myPhoneNumber!)) {
                  try {
                    await FirebaseFirestore.instance.collection('active_alerts').doc(myVar).delete();
                  } catch (e) {}
                }
              }
              _isDialogShowing = false;
              _isCallDialogShowing = false;
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('🔇 All Alarms & Flashlight Strobe Silenced!'), backgroundColor: Colors.green),
              );
            },
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen())),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.contacts),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ContactsScreen())),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  statusMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: primaryColor),
                ),
                const SizedBox(height: 16),

                GestureDetector(
                  onTap: _triggerSOS,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: primaryColor.withOpacity(0.5), blurRadius: 22, spreadRadius: 6)],
                    ),
                    child: CircleAvatar(
                      radius: 72,
                      backgroundColor: primaryColor,
                      child: const Text("SOS", style: TextStyle(fontSize: 38, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 2)),
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.redAccent.withOpacity(0.4)),
                  ),
                  child: Column(
                    children: [
                      const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text("🚓 PAKISTAN EMERGENCY SPEED-DIAL & DEFENSE CALL", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.redAccent, letterSpacing: 0.5)),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => _dialEmergencyNumber("15", "Police"),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red[800], foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4)),
                              child: const FittedBox(fit: BoxFit.scaleDown, child: Text("🚓 Police 15", style: TextStyle(fontWeight: FontWeight.bold))),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => _dialEmergencyNumber("1122", "Rescue"),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.green[800], foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4)),
                              child: const FittedBox(fit: BoxFit.scaleDown, child: Text("🚑 Rescue 1122", style: TextStyle(fontWeight: FontWeight.bold))),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => _dialEmergencyNumber("130", "Motorway"),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[800], foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4)),
                              child: const FittedBox(fit: BoxFit.scaleDown, child: Text("🛣️ NHMP 130", style: TextStyle(fontWeight: FontWeight.bold))),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () => _dialEmergencyNumber("1099", "Helpline"),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.purple[800], foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4)),
                              child: const FittedBox(fit: BoxFit.scaleDown, child: Text("🛡️ Rights 1099", style: TextStyle(fontWeight: FontWeight.bold))),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _triggerFakePoliceCall,
                          icon: const Icon(Icons.ring_volume_rounded, size: 17, color: Colors.redAccent),
                          label: const FittedBox(fit: BoxFit.scaleDown, child: Text("🚔 Trigger Fake Police 15 Incoming Call (5 Sec Delay)", style: TextStyle(fontWeight: FontWeight.bold))),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.indigo.withOpacity(0.4)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _toggleFlashlightStrobe(),
                              icon: Icon(_isStrobeActive ? Icons.flashlight_on : Icons.flashlight_off, color: Colors.white, size: 18),
                              label: FittedBox(fit: BoxFit.scaleDown, child: Text(_isStrobeActive ? "Stop SOS Strobe" : "SOS Torch Strobe")),
                              style: ElevatedButton.styleFrom(backgroundColor: _isStrobeActive ? Colors.amber[800] : Colors.indigo, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => _toggleBreadcrumbTracking(),
                              icon: Icon(_isBreadcrumbActive ? Icons.gps_fixed : Icons.route, color: Colors.white, size: 18),
                              label: FittedBox(fit: BoxFit.scaleDown, child: Text(_isBreadcrumbActive ? "Stop Live Trail" : "Live Trail (20s)")),
                              style: ElevatedButton.styleFrom(backgroundColor: _isBreadcrumbActive ? Colors.redAccent : Colors.deepPurple, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                        decoration: BoxDecoration(color: Colors.black.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
                        child: FittedBox(fit: BoxFit.scaleDown, child: Text("🛰️ $_liveTelemetryText", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(color: Colors.green.withOpacity(0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.green.withOpacity(0.5))),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _openEmergencyLiveChat,
                              icon: const Icon(Icons.mic_external_on_rounded, color: Colors.white, size: 18),
                              label: const FittedBox(fit: BoxFit.scaleDown, child: Text("Live Chat, Voice, Cam & Call", style: TextStyle(fontWeight: FontWeight.bold))),
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF075E54), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _triggerDirectWhatsAppOnly,
                              icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                              label: const FittedBox(fit: BoxFit.scaleDown, child: Text("WhatsApp SOS", style: TextStyle(fontWeight: FontWeight.bold))),
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF25D366), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.chat_bubble_rounded, color: Color(0xFF25D366), size: 18),
                          const SizedBox(width: 8),
                          const Expanded(child: Text("Auto-Launch External WhatsApp on SOS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                          Switch(value: _autoWhatsAppOnSOS, activeColor: const Color(0xFF25D366), materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, onChanged: (val) => setState(() => _autoWhatsAppOnSOS = val)),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.orange.withOpacity(0.5))),
                  child: Column(
                    children: [
                      const FittedBox(fit: BoxFit.scaleDown, child: Text("Dead-Man's Switch (Escort Mode + PIN Trap)", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange))),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text("Set Timer: ", style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange)),
                            child: DropdownButton<int>(
                              value: _selectedEscortMinutes,
                              underline: const SizedBox(),
                              icon: const Icon(Icons.arrow_drop_down, color: Colors.orange),
                              items: [1, 5, 10, 15, 30, 60].map((int value) => DropdownMenuItem<int>(value: value, child: Text("$value Min", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)))).toList(),
                              onChanged: (int? newValue) {
                                if (newValue != null) setState(() { _selectedEscortMinutes = newValue; });
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _startEscortMode,
                              icon: const Icon(Icons.timer, color: Colors.white, size: 18),
                              label: FittedBox(fit: BoxFit.scaleDown, child: Text("Start ($_selectedEscortMinutes Min)")),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8)),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _cancelEscortModeWithPinTrap,
                              icon: const Icon(Icons.lock_open_rounded, color: Colors.white, size: 18),
                              label: const FittedBox(fit: BoxFit.scaleDown, child: Text("I'm Safe (PIN)")),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[700], foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.teal.withOpacity(0.08), borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.teal.withOpacity(0.5))),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.battery_alert, color: Colors.teal, size: 20),
                          const SizedBox(width: 6),
                          Expanded(child: Text("Last Breath SOS (≤10% Bat • Now: $_currentBatteryLevel%)", style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold), maxLines: 2, overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: 4),
                          Switch(value: _lowBatteryProtectionEnabled, activeColor: Colors.teal, materialTapTargetSize: MaterialTapTargetSize.shrinkWrap, onChanged: (val) => setState(() => _lowBatteryProtectionEnabled = val)),
                        ],
                      ),
                      const Divider(height: 10),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: ElevatedButton.icon(
                              onPressed: _toggleSafeZone,
                              icon: Icon(_isSafeZoneActive ? Icons.lock : Icons.my_location, color: Colors.white, size: 18),
                              label: FittedBox(fit: BoxFit.scaleDown, child: Text(_isSafeZoneActive ? "Unlock Safe-Zone (150m)" : "Lock Safe-Zone (150m)")),
                              style: ElevatedButton.styleFrom(backgroundColor: _isSafeZoneActive ? Colors.redAccent : Colors.teal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: OutlinedButton(
                              onPressed: () => _triggerCustomSOS("LAST BREATH BATTERY ALERT! My phone battery is critically low ($_currentBatteryLevel%) and about to die."),
                              style: OutlinedButton.styleFrom(foregroundColor: Colors.teal, padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8)),
                              child: const FittedBox(fit: BoxFit.scaleDown, child: Text("Test Bat SOS", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),
                const Text("Developed by M Humza Arshad", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey, letterSpacing: 0.5)),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

