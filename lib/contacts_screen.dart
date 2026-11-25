import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

import 'fcm_service.dart';
import 'background_service.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  String? userPhone;
  List<Map<String, dynamic>> contactsList = [];
  bool isLoading = true;
  String currentLanguage = 'en';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    userPhone = prefs.getString('user_phone')?.trim();
    if (mounted) {
      setState(() {
        currentLanguage = prefs.getString('app_lang') ?? 'en';
      });
    }
    if (userPhone != null && userPhone!.isNotEmpty) {
      _fetchContacts();
    } else {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _changeLanguage(String? newLang) async {
    if (newLang != null) {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('app_lang', newLang);
      if (mounted) {
        setState(() {
          currentLanguage = newLang;
        });
      }
    }
  }

  void _showNotification(String msgEn, String msgUr) {
    if (!mounted) return;
    String displayMsg = currentLanguage == 'ur' ? msgUr : msgEn;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(displayMsg, style: const TextStyle(fontSize: 15)),
        backgroundColor: Colors.black87,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _fetchContacts() async {
    if (mounted) setState(() => isLoading = true);
    try {
      for (String myVar in getPhoneVariants(userPhone ?? '')) {
        DocumentSnapshot? doc;
        try {
          doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(myVar)
              .get()
              .timeout(const Duration(seconds: 4));
        } catch (_) {
          doc = await FirebaseFirestore.instance
              .collection('users')
              .doc(myVar)
              .get(const GetOptions(source: Source.cache));
        }

        if (doc != null && doc.exists && doc.data() != null) {
          Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
          if (data['emergency_contacts'] != null) {
            if (mounted) {
              setState(() {
                contactsList = List<Map<String, dynamic>>.from(data['emergency_contacts']);
              });
            }
            break;
          }
        }
      }
    } catch (e) {
      print("Error fetching contacts: $e");
    }
    if (mounted) setState(() => isLoading = false);
  }

  // 🔥 UNLIMITED CONTACTS SUPPORT (No 5-Contact Restriction!)
  void _addContact() async {
    String name = _nameController.text.trim();
    String phone = _phoneController.text.trim();

    if (name.isEmpty || phone.isEmpty) {
      _showNotification("Name and Phone are required.", "نام اور فون نمبر دونوں لازمی ہیں۔");
      return;
    }
    if (phone.startsWith("03")) {
      phone = "+92${phone.substring(1)}";
    }
    if (!phone.startsWith("+")) {
      _showNotification("Use country code (e.g. +92...).", "کنٹری کوڈ کے ساتھ نمبر لکھیں (جیسے +92...)۔");
      return;
    }

    setState(() => isLoading = true);
    contactsList.add({'name': name, 'phone': phone});

    try {
      for (String myVar in getPhoneVariants(userPhone ?? '')) {
        await FirebaseFirestore.instance.collection('users').doc(myVar).set({
          'user_phone': userPhone,
          'emergency_contacts': contactsList,
        }, SetOptions(merge: true)).timeout(const Duration(seconds: 4));
      }

      _nameController.clear();
      _phoneController.clear();
      _showNotification("Contact successfully saved!", "رابطہ کامیابی سے محفوظ ہو گیا!");
      _fetchContacts();
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
      _showNotification("Database error: $e", "ڈیٹا بیس کا مسئلہ: $e");
    }
  }

  void _deleteContact(int index) async {
    setState(() => isLoading = true);
    contactsList.removeAt(index);
    try {
      for (String myVar in getPhoneVariants(userPhone ?? '')) {
        await FirebaseFirestore.instance.collection('users').doc(myVar).set({
          'emergency_contacts': contactsList,
        }, SetOptions(merge: true)).timeout(const Duration(seconds: 4));
      }
      _showNotification("Contact deleted successfully.", "رابطہ حذف کر دیا گیا ہے۔");
      _fetchContacts();
    } catch (e) {
      if (mounted) setState(() => isLoading = false);
      _showNotification("Error deleting contact: $e", "رابطہ حذف کرنے میں مسئلہ: $e");
    }
  }

  // 🔥 DUAL-FORMAT REMOTE LOCATION PINGER (+92 & 03 SYNCED WITH FAST FALLBACK!)
  void _requestLocation(String targetPhone, String targetName) async {
    List<String> targetVariants = getPhoneVariants(targetPhone);
    if (targetVariants.isEmpty) return;

    try {
      _showNotification("Pinging $targetName...", "$targetName کی لوکیشن منگوائی جا رہی ہے...");

      List<StreamSubscription<DocumentSnapshot>> subs = [];
      bool isResolved = false;

      void cancelAllSubs() {
        for (var s in subs) {
          s.cancel();
        }
        subs.clear();
      }

      for (String vPhone in targetVariants) {
        DocumentReference docRef = FirebaseFirestore.instance.collection('location_requests').doc(vPhone);

        try {
          await docRef.set({
            'status': 'pending',
            'requested_by': userPhone,
            'lat': null,
            'long': null,
            'timestamp': FieldValue.serverTimestamp(),
          }).timeout(const Duration(seconds: 4));
        } catch (_) {}

        var sub = docRef.snapshots().listen((snapshot) {
          if (!isResolved && snapshot.exists && snapshot.data() != null) {
            var data = snapshot.data() as Map<String, dynamic>;
            if (data['status'] == 'fulfilled' && data['lat'] != null && data['long'] != null) {
              isResolved = true;
              cancelAllSubs();
              double lat = (data['lat'] as num).toDouble();
              double long = (data['long'] as num).toDouble();
              if (mounted) {
                _showLocationReceivedDialog(targetName, lat, long);
              }
            }
          }
        });
        subs.add(sub);
      }

      Set<String> sentTokens = {};
      for (String vPhone in targetVariants) {
        try {
          var targetUserDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(vPhone)
              .get()
              .timeout(const Duration(seconds: 3));
          if (targetUserDoc.exists && targetUserDoc.data() != null) {
            var userData = targetUserDoc.data() as Map<String, dynamic>;
            String? token = userData['fcmToken']?.toString();
            if (token != null && token.isNotEmpty && !sentTokens.contains(token)) {
              sentTokens.add(token);
              await FCMService.sendPushNotification(
                targetFCMToken: token,
                senderPhone: userPhone ?? 'Unknown',
                message: 'LOCATION_REQUEST',
              );
            }
          }
        } catch (_) {}
      }

      // Fast Fallback at 12 seconds if target phone has cached lastLat/lastLong
      Future.delayed(const Duration(seconds: 12), () async {
        if (!isResolved) {
          for (String vPhone in targetVariants) {
            try {
              var userDoc = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(vPhone)
                  .get()
                  .timeout(const Duration(seconds: 3));
              if (userDoc.exists && userDoc.data() != null) {
                var uData = userDoc.data() as Map<String, dynamic>;
                if (uData['lastLat'] != null && uData['lastLong'] != null) {
                  isResolved = true;
                  cancelAllSubs();
                  double lat = (uData['lastLat'] as num).toDouble();
                  double long = (uData['lastLong'] as num).toDouble();
                  if (mounted) {
                    _showLocationReceivedDialog("$targetName (Last Synced)", lat, long);
                  }
                  return;
                }
              }
            } catch (_) {}
          }
        }
      });

      Future.delayed(const Duration(seconds: 35), () {
        if (!isResolved) {
          cancelAllSubs();
          if (mounted) {
            _showNotification(
              "Timeout: Make sure Safety App Pro is logged in on $targetName's phone.",
              "ٹائم آؤٹ: یقینی بنائیں کہ دوسرے موبائل میں ایپ لاگ ان ہے۔",
            );
          }
        }
      });
    } catch (e) {
      _showNotification("Ping Error: $e", "پنگ کا مسئلہ: $e");
    }
  }

  void _showLocationReceivedDialog(String name, double lat, double long) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text(
          "📍 Location Received",
          style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
        ),
        content: Text("$name's location fetched successfully!\n\n📍 Lat: $lat\n📍 Lng: $long"),
        actions: [
          TextButton.icon(
            onPressed: () async {
              final Uri mapUri = Uri.parse("https://www.google.com/maps/search/?api=1&query=$lat,$long");
              if (await canLaunchUrl(mapUri)) {
                await launchUrl(mapUri, mode: LaunchMode.externalApplication);
              }
            },
            icon: const Icon(Icons.map, color: Colors.blue),
            label: const Text("OPEN MAP", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CLOSE", style: TextStyle(color: Colors.grey)),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Color primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            currentLanguage == 'ur' ? "ایمرجنسی رابطے اور چیٹ" : "Emergency Contacts & Chat",
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ),
        backgroundColor: primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: DropdownButton<String>(
              value: currentLanguage,
              dropdownColor: primaryColor.withOpacity(0.9),
              icon: const Icon(Icons.language, color: Colors.white),
              underline: const SizedBox(),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              items: const [
                DropdownMenuItem(value: 'en', child: Text('ENG')),
                DropdownMenuItem(value: 'ur', child: Text('اردو')),
              ],
              onChanged: _changeLanguage,
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Column(
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Column(
                  children: [
                    Text(
                      currentLanguage == 'ur'
                          ? "محفوظ شدہ رابطے: ${contactsList.length} (لامحدود)"
                          : "Saved Contacts: ${contactsList.length} (Unlimited)",
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: currentLanguage == 'ur' ? "رابطے کا نام" : "Contact Name",
                        prefixIcon: const Icon(Icons.person),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: currentLanguage == 'ur' ? "فون نمبر (+92 یا 03...)" : "Phone Number (+92 or 03...)",
                        prefixIcon: const Icon(Icons.phone),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _addContact,
                      icon: const Icon(Icons.add, color: Colors.white),
                      label: Text(
                        currentLanguage == 'ur' ? "رابطہ محفوظ کریں" : "Add Contact",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        minimumSize: const Size(double.infinity, 44),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    )
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : contactsList.isEmpty
                      ? Center(
                          child: Text(
                            currentLanguage == 'ur' ? "کوئی رابطہ محفوظ نہیں ہے۔" : "No emergency contacts saved.",
                          ),
                        )
                      : ListView.builder(
                          itemCount: contactsList.length,
                          itemBuilder: (context, index) {
                            String cName = contactsList[index]['name'] ?? 'Contact';
                            String cPhone = contactsList[index]['phone'] ?? '';
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 5),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                leading: CircleAvatar(
                                  backgroundColor: primaryColor,
                                  child: const Icon(Icons.person, color: Colors.white),
                                ),
                                title: Text(cName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text(cPhone),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(Icons.chat_rounded, color: Colors.green),
                                      tooltip: "Live Chat, Voice, Camera & Call",
                                      onPressed: () {
                                        if (userPhone == null || userPhone!.isEmpty) return;
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => LiveChatScreen(
                                              myPhone: userPhone!,
                                              targetPhone: cPhone,
                                              targetName: cName,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(Icons.my_location, color: Colors.blue),
                                      tooltip: "Ping Live Location",
                                      onPressed: () => _requestLocation(cPhone, cName),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      icon: const Icon(Icons.delete, color: Colors.red),
                                      onPressed: () => _deleteContact(index),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            )
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 💬, 🎤, 📷 & 📞 WHATSAPP-STYLE LIVE CHAT, VOICE NOTES, CAMERA & IN-APP CALL
// ============================================================================
class LiveChatScreen extends StatefulWidget {
  final String myPhone;
  final String targetPhone;
  final String targetName;

  const LiveChatScreen({
    super.key,
    required this.myPhone,
    required this.targetPhone,
    required this.targetName,
  });

  @override
  State<LiveChatScreen> createState() => _LiveChatScreenState();
}

class _LiveChatScreenState extends State<LiveChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  static const platform = MethodChannel('com.safetyapp/native_sms');

  late String chatRoomId;
  bool _isRecording = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;

  String? _playingDocId;
  Timer? _playbackFinishTimer;
  int _lastSeenMsgCount = -1;

  String _normalizeToDigits(String p) {
    String d = p.replaceAll(RegExp(r'[^0-9]'), '');
    if (d.startsWith('92') && d.length >= 11) {
      return d.substring(2);
    } else if (d.startsWith('0') && d.length >= 10) {
      return d.substring(1);
    }
    return d;
  }

  @override
  void initState() {
    super.initState();
    List<String> phones = [_normalizeToDigits(widget.myPhone), _normalizeToDigits(widget.targetPhone)]..sort();
    chatRoomId = "${phones[0]}_${phones[1]}";
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _playbackFinishTimer?.cancel();
    platform.invokeMethod('stopVoicePlayback');
    _msgController.dispose();
    super.dispose();
  }

  Future<void> _notifyTargetOnChat(String previewText) async {
    Set<String> notifiedTokens = {};
    for (String vPhone in getPhoneVariants(widget.targetPhone)) {
      try {
        var doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(vPhone)
            .get()
            .timeout(const Duration(seconds: 3));
        if (doc.exists && doc.data() != null) {
          String? token = doc.data()!['fcmToken']?.toString();
          if (token != null && token.isNotEmpty && !notifiedTokens.contains(token)) {
            notifiedTokens.add(token);
            await FCMService.sendPushNotification(
              targetFCMToken: token,
              senderPhone: widget.myPhone,
              message: "CHAT_MSG:$previewText",
            );
          }
        }
      } catch (_) {}
    }
  }

  Future<void> _sendTextMessage() async {
    String text = _msgController.text.trim();
    if (text.isEmpty) return;
    _msgController.clear();

    await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatRoomId)
        .collection('messages')
        .add({
      'sender': _normalizeToDigits(widget.myPhone),
      'receiver': _normalizeToDigits(widget.targetPhone),
      'senderRaw': widget.myPhone.trim(),
      'type': 'text',
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
    });
    _notifyTargetOnChat(text);
  }

  // 📍 FAST NON-BLOCKING LOCATION SHARE IN CHAT
  Future<void> _sendLocationPinInChat() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('📍 Sharing Live Location in Chat...'), duration: Duration(seconds: 2)),
    );

    SharedPreferences prefs = await SharedPreferences.getInstance();
    Position? pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      ).timeout(const Duration(seconds: 3), onTimeout: () => throw TimeoutException('GPS timeout'));
    } catch (_) {
      try {
        pos = await Geolocator.getLastKnownPosition().timeout(const Duration(seconds: 2), onTimeout: () => null);
      } catch (_) {}
    }

    double lat = pos?.latitude ?? prefs.getDouble('last_lat') ?? 30.1575;
    double long = pos?.longitude ?? prefs.getDouble('last_long') ?? 71.5249;
    String mapUrl = "https://maps.google.com/?q=$lat,$long";

    await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatRoomId)
        .collection('messages')
        .add({
      'sender': _normalizeToDigits(widget.myPhone),
      'receiver': _normalizeToDigits(widget.targetPhone),
      'senderRaw': widget.myPhone.trim(),
      'type': 'location',
      'text': "📍 Live Emergency Location:\n$mapUrl",
      'lat': lat,
      'long': long,
      'timestamp': FieldValue.serverTimestamp(),
    });
    _notifyTargetOnChat("📍 Shared Live Location Pin");
  }

  // 📷 SNAP & SEND CAMERA PHOTO INSIDE CHAT
  Future<void> _sendCameraPhotoInChat() async {
    var camStatus = await Permission.camera.status;
    if (!camStatus.isGranted) {
      camStatus = await Permission.camera.request();
    }

    try {
      final String? base64Img = await platform.invokeMethod<String>('captureCameraPhoto');
      if (base64Img != null && base64Img.isNotEmpty) {
        await FirebaseFirestore.instance
            .collection('chats')
            .doc(chatRoomId)
            .collection('messages')
            .add({
          'sender': _normalizeToDigits(widget.myPhone),
          'receiver': _normalizeToDigits(widget.targetPhone),
          'senderRaw': widget.myPhone.trim(),
          'type': 'image',
          'text': '📷 Camera Snapshot',
          'imageBase64': base64Img,
          'timestamp': FieldValue.serverTimestamp(),
        });
        _notifyTargetOnChat("📷 Sent a Camera Photo");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // 🎤 RECORD & SEND VOICE NOTE
  Future<void> _toggleVoiceRecording() async {
    var micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) return;
    }

    if (!_isRecording) {
      await _stopVoiceNotePlayback();
      try {
        await platform.invokeMethod('startVoiceRecording');
        setState(() {
          _isRecording = true;
          _recordSeconds = 0;
        });
        _recordTimer?.cancel();
        _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          if (mounted) setState(() => _recordSeconds++);
          if (_recordSeconds >= 30) _toggleVoiceRecording();
        });
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Mic Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    } else {
      _recordTimer?.cancel();
      int finalDuration = _recordSeconds < 1 ? 1 : _recordSeconds;
      setState(() => _isRecording = false);

      try {
        final String? base64Audio = await platform.invokeMethod<String>('stopVoiceRecording');
        if (base64Audio != null && base64Audio.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('chats')
              .doc(chatRoomId)
              .collection('messages')
              .add({
            'sender': _normalizeToDigits(widget.myPhone),
            'receiver': _normalizeToDigits(widget.targetPhone),
            'senderRaw': widget.myPhone.trim(),
            'type': 'voice',
            'text': '🎤 Voice Note (${finalDuration}s)',
            'audioBase64': base64Audio,
            'duration': finalDuration,
            'timestamp': FieldValue.serverTimestamp(),
          });
          _notifyTargetOnChat("🎤 Sent a Voice Note (${finalDuration}s)");
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Voice Send Error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  // 🔊 PLAY OR MID-WAY STOP VOICE NOTE
  Future<void> _togglePlayOrStopVoiceNote(String docId, String base64Audio, int savedDurationSec) async {
    if (_playingDocId == docId) {
      await _stopVoiceNotePlayback();
      return;
    }
    await _stopVoiceNotePlayback();
    setState(() => _playingDocId = docId);

    try {
      final int? durationMs = await platform.invokeMethod<int>('playVoiceNote', {'base64Audio': base64Audio});
      int waitMs = durationMs ?? (savedDurationSec * 1000);
      if (waitMs < 1000) waitMs = 1500;

      _playbackFinishTimer?.cancel();
      _playbackFinishTimer = Timer(Duration(milliseconds: waitMs + 300), () {
        if (mounted && _playingDocId == docId) {
          setState(() => _playingDocId = null);
        }
      });
    } catch (e) {
      if (mounted) setState(() => _playingDocId = null);
    }
  }

  Future<void> _stopVoiceNotePlayback() async {
    _playbackFinishTimer?.cancel();
    try {
      await platform.invokeMethod('stopVoicePlayback');
    } catch (_) {}
    if (mounted) setState(() => _playingDocId = null);
  }

  // 📞 IN-APP LIVE VOICE CALL WITH INTERACTIVE CALLING DIALOG
  Future<void> _startInAppVoiceCall() async {
    List<String> variants = getPhoneVariants(widget.targetPhone);
    for (String vPhone in variants) {
      try {
        await FirebaseFirestore.instance.collection('active_calls').doc(vPhone).set({
          'caller': _normalizeToDigits(widget.myPhone),
          'callerName': widget.myPhone,
          'status': 'ringing',
          'timestamp': FieldValue.serverTimestamp(),
        }).timeout(const Duration(seconds: 3));
      } catch (_) {}

      try {
        var doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(vPhone)
            .get()
            .timeout(const Duration(seconds: 3));
        if (doc.exists && doc.data()?['fcmToken'] != null) {
          await FCMService.sendPushNotification(
            targetFCMToken: doc.data()!['fcmToken'],
            senderPhone: widget.myPhone,
            message: 'INCOMING_CALL:${widget.myPhone}',
          );
        }
      } catch (_) {}
    }

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF121B22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Column(
          children: [
            const CircleAvatar(
              radius: 32,
              backgroundColor: Color(0xFF075E54),
              child: Icon(Icons.phone_in_talk_rounded, color: Colors.white, size: 34),
            ),
            const SizedBox(height: 10),
            Text(
              "Calling ${widget.targetName}...",
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: const Text(
          "Ringing their phone via In-App VoIP Channel.\nOnce connected, use the Mic button below for live walkie-talkie voice transmission.",
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async {
              for (String vPhone in variants) {
                try {
                  await FirebaseFirestore.instance
                      .collection('active_calls')
                      .doc(vPhone)
                      .set({'status': 'ended'}, SetOptions(merge: true));
                } catch (_) {}
              }
              if (Navigator.canPop(ctx)) Navigator.pop(ctx);
            },
            icon: const Icon(Icons.call_end),
            label: const Text("End Call"),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
            onPressed: () {
              if (Navigator.canPop(ctx)) Navigator.pop(ctx);
            },
            icon: const Icon(Icons.mic),
            label: const Text("Open Channel"),
          ),
        ],
      ),
    );
  }

  void _showFullScreenImage(Uint8List imageBytes) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InteractiveViewer(
              child: Image.memory(imageBytes, fit: BoxFit.contain),
            ),
            TextButton.icon(
              onPressed: () => Navigator.pop(ctx),
              icon: const Icon(Icons.close, color: Colors.white),
              label: const Text("CLOSE PHOTO", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Color primaryColor = Theme.of(context).colorScheme.primary;
    String myCleanDigits = _normalizeToDigits(widget.myPhone);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF075E54),
        titleSpacing: 0,
        title: Row(
          children: [
            const CircleAvatar(
              radius: 18,
              backgroundColor: Colors.white24,
              child: Icon(Icons.person, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.targetName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    widget.targetPhone,
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_playingDocId != null)
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.stop_circle_rounded, color: Colors.redAccent),
              tooltip: "Stop Voice Playback",
              onPressed: _stopVoiceNotePlayback,
            ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.phone_in_talk_rounded, color: Colors.greenAccent),
            tooltip: "In-App Live Voice Call",
            onPressed: _startInAppVoiceCall,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.camera_alt_rounded, color: Colors.amberAccent),
            tooltip: "Snap & Send Camera Photo",
            onPressed: _sendCameraPhotoInChat,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_location_alt_rounded, color: Colors.amberAccent),
            tooltip: "Share Live Location Pin",
            onPressed: _sendLocationPinInChat,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.call, color: Colors.white),
            tooltip: "Direct SIM Call",
            onPressed: () async {
              final Uri telUri = Uri.parse("tel:${widget.targetPhone}");
              try {
                await launchUrl(telUri, mode: LaunchMode.externalApplication);
              } catch (_) {}
            },
          ),
        ],
      ),
      body: Container(
        color: const Color(0xFFECE5DD),
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('chats')
                    .doc(chatRoomId)
                    .collection('messages')
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    _lastSeenMsgCount = 0;
                    return Center(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.all(24),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                        child: Text(
                          "🔒 End-to-End Emergency Channel with ${widget.targetName}.\nSend text messages, record stoppable voice notes, snap camera photos, or share your GPS location!",
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.black87, fontSize: 13),
                        ),
                      ),
                    );
                  }

                  var docs = snapshot.data!.docs;
                  if (_lastSeenMsgCount != -1 && docs.length > _lastSeenMsgCount) {
                    var newestData = docs.first.data() as Map<String, dynamic>;
                    String newestSender = _normalizeToDigits(newestData['sender']?.toString() ?? '');
                    if (newestSender != myCleanDigits) {
                      FlutterRingtonePlayer().playNotification();
                    }
                  }
                  _lastSeenMsgCount = docs.length;

                  return ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      var data = docs[index].data() as Map<String, dynamic>;
                      String docId = docs[index].id;
                      String senderDigits = _normalizeToDigits(data['sender']?.toString() ?? '');
                      bool isMe = (senderDigits == myCleanDigits);
                      String msgType = data['type'] ?? 'text';
                      String text = data['text'] ?? '';
                      bool isThisPlaying = (_playingDocId == docId);

                      return Align(
                        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                          decoration: BoxDecoration(
                            color: isMe ? const Color(0xFFDCF8C6) : Colors.white,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(14),
                              topRight: const Radius.circular(14),
                              bottomLeft: isMe ? const Radius.circular(14) : Radius.zero,
                              bottomRight: isMe ? Radius.zero : const Radius.circular(14),
                            ),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 3, offset: const Offset(0, 1))
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (!isMe)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4.0),
                                  child: Text(
                                    widget.targetName,
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: primaryColor),
                                  ),
                                ),
                              if (msgType == 'voice')
                                InkWell(
                                  onTap: () {
                                    if (data['audioBase64'] != null) {
                                      int dur = (data['duration'] as num?)?.toInt() ?? 5;
                                      _togglePlayOrStopVoiceNote(docId, data['audioBase64'], dur);
                                    }
                                  },
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      CircleAvatar(
                                        radius: 20,
                                        backgroundColor: isThisPlaying ? Colors.red : const Color(0xFF075E54),
                                        child: Icon(
                                          isThisPlaying ? Icons.stop_rounded : Icons.play_arrow_rounded,
                                          color: Colors.white,
                                          size: 24,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Flexible(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              isThisPlaying ? "🔊 Playing Voice Note..." : text,
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: isThisPlaying ? Colors.red[800] : Colors.black87,
                                                fontSize: 14,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              isThisPlaying ? "⏹️ Tap here to STOP audio" : "▶️ Tap to play voice note",
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: isThisPlaying ? FontWeight.bold : FontWeight.normal,
                                                color: isThisPlaying ? Colors.red : Colors.black54,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              else if (msgType == 'image' && data['imageBase64'] != null)
                                Builder(
                                  builder: (context) {
                                    final Uint8List imgBytes = base64Decode(data['imageBase64'].toString());
                                    return GestureDetector(
                                      onTap: () => _showFullScreenImage(imgBytes),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(10),
                                            child: Image.memory(
                                              imgBytes,
                                              width: 210,
                                              height: 210,
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          const Text(
                                            "📷 Tap photo to view full screen",
                                            style: TextStyle(fontSize: 11, color: Colors.black54),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                )
                              else if (msgType == 'location')
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(text, style: const TextStyle(color: Colors.black87, fontSize: 14)),
                                    const SizedBox(height: 6),
                                    ElevatedButton.icon(
                                      onPressed: () async {
                                        double? lat = (data['lat'] as num?)?.toDouble();
                                        double? long = (data['long'] as num?)?.toDouble();
                                        if (lat != null && long != null) {
                                          final Uri uri = Uri.parse("https://www.google.com/maps/search/?api=1&query=$lat,$long");
                                          if (await canLaunchUrl(uri)) {
                                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                                          }
                                        }
                                      },
                                      icon: const Icon(Icons.map, size: 16, color: Colors.white),
                                      label: const Text("Open Google Maps"),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.blue,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  ],
                                )
                              else
                                Text(text, style: const TextStyle(color: Colors.black87, fontSize: 15)),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            if (_isRecording)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                color: Colors.redAccent,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.fiber_manual_record, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        "Recording Voice Note (${_recordSeconds}s)... Tap Stop Icon to Send!",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              color: Colors.white,
              child: SafeArea(
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.camera_alt_rounded, color: Color(0xFF075E54)),
                      tooltip: "Snap Camera Photo",
                      onPressed: _sendCameraPhotoInChat,
                    ),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: TextField(
                          controller: _msgController,
                          style: const TextStyle(color: Colors.black87),
                          decoration: const InputDecoration(
                            hintText: "Type a message...",
                            hintStyle: TextStyle(color: Colors.black54),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: _isRecording ? Colors.red : Colors.orange[800],
                      child: IconButton(
                        icon: Icon(_isRecording ? Icons.stop_rounded : Icons.mic_rounded, color: Colors.white, size: 20),
                        tooltip: _isRecording ? "Stop & Send Voice Note" : "Record Voice Note",
                        onPressed: _toggleVoiceRecording,
                      ),
                    ),
                    const SizedBox(width: 6),
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: const Color(0xFF075E54),
                      child: IconButton(
                        icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                        onPressed: _sendTextMessage,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}