import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GuideScreen extends StatefulWidget {
  const GuideScreen({super.key});

  @override
  State<GuideScreen> createState() => _GuideScreenState();
}

class _GuideScreenState extends State<GuideScreen> {
  String currentLanguage = 'en';

  @override
  void initState() {
    super.initState();
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        currentLanguage = prefs.getString('app_lang') ?? 'en';
      });
    }
  }

  Future<void> _changeLanguage(String? newLang) async {
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

  final List<Map<String, dynamic>> _guideItems = [
    {
      'icon': Icons.sos_rounded,
      'color': Colors.red,
      'title_en': '1. Instant Multi-Channel SOS & Panic Shake',
      'title_ur': '1. ون ٹیپ SOS اور پینک شیک (ہلانا)',
      'purpose_en': 'Purpose: Instant multi-channel distress dispatch during life-threatening situations.',
      'purpose_ur': 'مقصد: جان کے خطرے کی صورت میں بیک وقت تمام ذرائع سے فوری مدد طلب کرنا۔',
      'desc_en':
          'Tap the giant red SOS button OR violently shake your phone (>20G). Within 3 seconds, the app fetches your GPS coordinates, sends background SIM SMS to all contacts, triggers loud Cloud FCM sirens & main-screen pop-up banners on their phones, turns on the Flashlight Strobe, and starts Live Breadcrumb tracking.',
      'desc_ur':
          'بڑا سرخ SOS بٹن دبائیں یا موبائل کو زور سے ہلائیں۔ ایپ 3 سیکنڈ کے اندر آپ کی لوکیشن نکال کر سم کے ذریعے بیک گراؤنڈ SMS بھیجے گی، دوسرے فونز کی اسکرین پر پاپ اپ نوٹیفکیشن اور لاؤڈ الارم بجائے گی، فلیش لائٹ اسٹروب آن کرے گی اور لائیو ٹریکنگ شروع کر دے گی۔',
    },
    {
      'icon': Icons.sensors_rounded,
      'color': Colors.deepOrange,
      'title_en': '2. Automated Hardware Fall Detection',
      'title_ur': '2. خودکار فال ڈیٹیکشن (گرنے کی شناخت)',
      'purpose_en': 'Purpose: Saves lives if you fall unconscious due to a road accident or medical emergency.',
      'purpose_ur': 'مقصد: حادثے یا چکر آ کر گرنے اور بے ہوش ہونے کی صورت میں خودکار مدد بھیجنا۔',
      'desc_en':
          'The background engine continuously monitors the 3-axis accelerometer using √(x²+y²+z²). If a sudden freefall (<3G) or heavy impact (>20G) occurs, it dispatches emergency alerts even if your phone is locked or the app is closed.',
      'desc_ur':
          'بیک گراؤنڈ انجن ایکسلرومیٹر سینسر کے ذریعے گرنے یا شدید جھٹکے کو نوٹ کرتا ہے۔ اگر آپ اچانک گر جائیں اور ایپ بند بھی ہو، تب بھی یہ خودکار طور پر گھر والوں کو لوکیشن اور الرٹ بھیج دیتا ہے۔',
    },
    {
      'icon': Icons.chat_rounded,
      'color': const Color(0xFF075E54),
      'title_en': '3. 2-Way Live Chat, Stoppable Voice Notes & Camera',
      'title_ur': '3. لائیو چیٹ، وائس نوٹ اور کیمرہ فوٹو',
      'purpose_en': 'Purpose: Real-time communication with text, mid-way stoppable voice notes, and live camera evidence.',
      'purpose_ur': 'مقصد: ایمرجنسی میں پیغام، آواز اور کیمرے کی تصویر بطور ثبوت فوری بھیجنا۔',
      'desc_en':
          'Open Live Chat from the top bar, main card, or Contacts screen:\n• Send instant text messages & 1-tap GPS pins.\n• Tap the Mic to record Voice Notes. While listening, tap the red Stop button anytime to stop playback mid-way.\n• Tap the Camera icon to snap and send a live photo directly inside the chat!',
      'desc_ur':
          'لائیو چیٹ کھول کر آپ ٹیکسٹ میسج اور لوکیشن پن بھیج سکتے ہیں۔ مائیک دبا کر وائس نوٹ بھیجیں اور سنتے وقت جب چاہیں اسٹاپ بٹن سے آواز درمیان میں روک دیں۔ کیمرہ آئیکن دبا کر فوری تصویر کھینچ کر چیٹ میں بھیجیں۔',
    },
    {
      'icon': Icons.phone_in_talk_rounded,
      'color': Colors.green,
      'title_en': '4. In-App Live Voice Call (Walkie-Talkie / VoIP)',
      'title_ur': '4. ایپ کے اندر براہِ راست لائیو کال',
      'purpose_en': 'Purpose: Call your emergency contact directly inside the app over internet when SIM balance is zero.',
      'purpose_ur': 'مقصد: سم بیلنس نہ ہونے پر انٹرنیٹ کے ذریعے ایپ کے اندر ہی لائیو بات چیت کرنا۔',
      'desc_en':
          'Inside the Live Chat screen, tap the Live Call icon. The other phone receives a full-screen Incoming Call alert with ringtone (even if their app is closed) and can accept to talk immediately.',
      'desc_ur':
          'چیٹ اسکرین کے اوپر کال بٹن دبائیں۔ دوسرے موبائل کی اسکرین پر فوری انکمنگ کال شو ہو گی اور دونوں طرف سے براہِ راست بات ہو سکے گی۔',
    },
    {
      'icon': Icons.my_location_rounded,
      'color': Colors.blue,
      'title_en': '5. Remote Location Ping & Unlimited Contacts',
      'title_ur': '5. دوسرے موبائل کی لوکیشن منگوانا اور لامحدود رابطے',
      'purpose_en': 'Purpose: Add unlimited emergency contacts and fetch their live GPS remotely without them touching their phone.',
      'purpose_ur': 'مقصد: لامحدود ایمرجنسی نمبرز محفوظ کرنا اور دوسرے فرد کے فون کو ہاتھ لگائے بغیر اس کی لائیو لوکیشن منگوانا۔',
      'desc_en':
          'Go to Emergency Contacts (save unlimited numbers!) and tap the blue Location icon next to any contact. Our Dual-Format (+92 & 03) GPS Engine wakes up their closed phone silently and displays their exact Google Maps pin.',
      'desc_ur':
          'ایمرجنسی رابطوں میں جا کر جتنے مرضی نمبرز محفوظ کریں اور کسی بھی نمبر کے آگے نیلا لوکیشن بٹن دبائیں۔ دوسرے موبائل کی ایپ بند ہونے کے باوجود سسٹم خاموشی سے اس کی لوکیشن نکال کر نقشے پر دکھا دے گا۔',
    },
    {
      'icon': Icons.timer_rounded,
      'color': Colors.orange,
      'title_en': '6. Escort Mode (Dead-Man Switch) & Hostage PIN Trap',
      'title_ur': '6. ایسکورٹ موڈ (ٹائمر) اور خفیہ پن ٹریپ',
      'purpose_en': 'Purpose: Automatic SOS if you fail to reach home safely within the set time, protected against attackers.',
      'purpose_ur': 'مقصد: مقررہ وقت پر محفوظ نہ پہنچنے یا اغوا کار کے زبردستی بند کرنے پر الرٹ بھیجنا۔',
      'desc_en':
          'Set a timer (1–60 mins) before traveling. It fires SOS automatically if time expires.\n• Normal Safe PIN (1234): Safely cancels the timer.\n• Duress/Hostage PIN (9999) or Wrong PIN: Shows a fake "Cancelled" message to trick an attacker while silently dispatching a Hostage SOS alert!',
      'desc_ur':
          'سفر سے پہلے ٹائمر لگائیں۔ وقت ختم ہونے پر خودکار الرٹ جائے گا۔\n• اصلی پن (1234): ٹائمر بحفاظت بند کرے گا۔\n• خطرے کا پن (9999) یا غلط پن: حملہ آور کو دھوکہ دینے کے لیے اسکرین پر ٹائمر بند دکھائے گا لیکن خفیہ طور پر ایمرجنسی الرٹ بھیج دے گا!',
    },
    {
      'icon': Icons.wifi_tethering_rounded,
      'color': Colors.purple,
      'title_en': '7. Offline P2P Mesh Network (Zero Net / Zero SIM)',
      'title_ur': '7. آف لائن میش نیٹ ورک (بغیر انٹرنیٹ اور سم سگنل)',
      'purpose_en': 'Purpose: Broadcast distress signals to nearby phones in dead zones with zero cellular or Wi-Fi coverage.',
      'purpose_ur': 'مقصد: جہاں انٹرنیٹ اور سم کے سگنل بالکل نہ ہوں وہاں قریبی موبائلز تک مدد کا پیغام پہنچانا۔',
      'desc_en':
          'When internet is disconnected, pressing SOS automatically activates P2P Cluster Mesh (Bluetooth + Wi-Fi Direct). Any phone within 10–30 meters running Safety App Pro will catch the signal and sound a loud rescue alarm.',
      'desc_ur':
          'انٹرنیٹ اور سم سگنل نہ ہونے پر ایپ خودکار طور پر بلوٹوتھ اور وائی فائی ڈائریکٹ کے ذریعے قریبی 30 میٹر کے دائرے میں موجود موبائلز پر ایمرجنسی الارم اور لوکیشن بھیج دیتی ہے۔',
    },
    {
      'icon': Icons.battery_alert_rounded,
      'color': Colors.teal,
      'title_en': '8. Low-Battery "Last Breath" & Safe-Zone (150m)',
      'title_ur': '8. لو بیٹری لاسٹ بریتھ اور سیف زون (150 میٹر)',
      'purpose_en': 'Purpose: Send last known location before battery dies (≤10%) and guard a 150m safety perimeter.',
      'purpose_ur': 'مقصد: فون بند ہونے سے پہلے آخری لوکیشن بھیجنا اور 150 میٹر کے محفوظ دائرے کی نگرانی۔',
      'desc_en':
          '• Last Breath SOS: Automatically sends your GPS coordinates when battery drops to 10% or below.\n• Safe-Zone Lock: Instantly locks your current spot; if you move more than 150 meters away, an automatic breach SOS is fired.',
      'desc_ur':
          '• بیٹری 10 فیصد رہ جانے پر فون بند ہونے سے پہلے خودکار طور پر آخری لوکیشن گھر والوں کو بھیج دیتا ہے۔\n• سیف زون لاک کرنے پر اگر صارف 150 میٹر کے دائرے سے باہر نکلے تو خودکار الرٹ چلا جاتا ہے۔',
    },
    {
      'icon': Icons.flashlight_on_rounded,
      'color': Colors.indigo,
      'title_en': '9. Hardware Torch Strobe & Live Breadcrumb Trail (20s)',
      'title_ur': '9. فلیش لائٹ اسٹروب اور لائیو اسپیڈ ٹریکنگ',
      'purpose_en': 'Purpose: Visual night-rescue beacon and continuous 20-second vehicle speed & route tracking.',
      'purpose_ur': 'مقصد: رات کے اندھیرے میں روشنی کا سگنل دینا اور چلتی گاڑی کی رفتار و راستہ ٹریک کرنا۔',
      'desc_en':
          '• SOS Torch Strobe: Blinks the rear LED camera flash every 250ms to guide rescuers at night.\n• Live Trail (20s): Pushes your moving GPS coordinates and speed (km/h) to the cloud every 20 seconds.',
      'desc_ur':
          '• اسٹروب لائٹ: رات کے وقت ریسکیو ٹیم کو متوجہ کرنے کے لیے موبائل کی ٹارچ تیزی سے بلنک کرتی ہے۔\n• لائیو ٹریل: ہر 20 سیکنڈ بعد آپ کی بدلتی ہوئی لوکیشن اور گاڑی کی رفتار (km/h) اپڈیٹ کرتی ہے۔',
    },
    {
      'icon': Icons.local_police_rounded,
      'color': Colors.redAccent,
      'title_en': '10. Pakistan Emergency Speed-Dial & Fake Police Call',
      'title_ur': '10. پاکستان ایمرجنسی اسپیڈ ڈائل اور فیک پولیس کال',
      'purpose_en': 'Purpose: 1-tap calling to national helplines (15, 1122, 130, 1099) & psychological defense call.',
      'purpose_ur': 'مقصد: ایک کلک پر 15، 1122، 130 پر کال کرنا اور مشکوک صورتحال میں نقلی پولیس کال بجانا۔',
      'desc_en':
          '• Speed-Dial Bar: Instant 1-tap dialer for Police (15), Rescue (1122), Motorway Police (130), and Human Rights (1099).\n• Fake Police Call: Triggers a realistic incoming call from "Police Control Room (15)" after 5 seconds to deter suspicious drivers or strangers.',
      'desc_ur':
          '• اسپیڈ ڈائل بار سے فوری طور پر پولیس 15، ریسکیو 1122، موٹروے 130 یا 1099 ملائیں۔\n• فیک پولیس کال دبانے سے 5 سیکنڈ بعد آپ کے فون پر اصلی جیسی پولیس کنٹرول روم کی کال آئے گی جس سے مشکوک شخص خوفزدہ ہو جائے گا۔',
    },
    {
      'icon': Icons.menu_open_rounded,
      'color': Colors.brown,
      'title_en': '11. ☰ Three-Lines Feature Catalog Menu & Direct WhatsApp',
      'title_ur': '11. تھری لائنز فیچر مینو اور ڈائریکٹ واٹس ایپ الرٹ',
      'purpose_en': 'Purpose: Quick access to all 12 features with detailed explanations & direct external WhatsApp dispatch.',
      'purpose_ur': 'مقصد: تمام 12 فیچرز کی تفصیل ایک جگہ دیکھنا اور براہِ راست واٹس ایپ پر لوکیشن بھیجنا۔',
      'desc_en':
          'Tap the top-left ☰ Three-Lines icon on the main screen to open the complete Feature Catalog where every tool’s purpose is explained and can be launched with one tap.',
      'desc_ur':
          'مین اسکرین کے بائیں کونے پر موجود تین لائنوں (☰) والے بٹن کو دبائیں جہاں تمام فیچرز کی فہرست اور ان کا مقصد درج ہے اور وہیں سے انہیں چلایا بھی جا سکتا ہے۔',
    },
  ];

  @override
  Widget build(BuildContext context) {
    Color primaryColor = Theme.of(context).colorScheme.primary;
    bool isUr = (currentLanguage == 'ur');

    return Scaffold(
      appBar: AppBar(
        backgroundColor: primaryColor,
        iconTheme: const IconThemeData(color: Colors.white),
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            isUr ? "مکمل یوزر گائیڈ (Safety App Pro)" : "Complete User Guide & Manual",
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: DropdownButton<String>(
              value: currentLanguage,
              dropdownColor: primaryColor.withOpacity(0.95),
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
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [primaryColor, Colors.black87],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                const Icon(Icons.shield_rounded, color: Colors.amberAccent, size: 42),
                const SizedBox(height: 8),
                Text(
                  isUr
                      ? "سیفٹی ایپ پرو — تمام فیچرز اور ان کا استعمال"
                      : "Safety App Pro — Complete Feature Architecture",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  "Designed & Developed by M Humza Arshad",
                  style: TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ..._guideItems.map((item) {
            return Card(
              elevation: 2,
              margin: const EdgeInsets.symmetric(vertical: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Column(
                  crossAxisAlignment: isUr ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: (item['color'] as Color).withOpacity(0.15),
                          child: Icon(item['icon'] as IconData, color: item['color'] as Color),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            isUr ? item['title_ur'] : item['title_en'],
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: item['color'] as Color,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: (item['color'] as Color).withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isUr ? item['purpose_ur'] : item['purpose_en'],
                        textAlign: isUr ? TextAlign.right : TextAlign.left,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isUr ? item['desc_ur'] : item['desc_en'],
                      textAlign: isUr ? TextAlign.right : TextAlign.left,
                      style: const TextStyle(fontSize: 13.5, height: 1.45),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}