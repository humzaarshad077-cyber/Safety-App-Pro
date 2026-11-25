import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart'; // MainScreen par shift hone ke liye

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phoneController = TextEditingController();

  void _loginWithoutOTP() async {
    String phone = _phoneController.text.trim();
    
    // Sirf basic check ke number format theek hai
    if (phone.isEmpty || !phone.startsWith("+")) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Country code ke sath number likhein (e.g. +92300...)")),
      );
      return;
    }

    // Phone ki local storage mein number save kar lo (Yeh user ki ID ban gayi)
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_phone', phone);

    // Direct Main Screen par bhej do bina kisi OTP ke!
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const MainScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Safety App - Setup ID', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        backgroundColor: const Color(0xFFE53935),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.security_outlined, size: 100, color: Color(0xFFE53935)),
            const SizedBox(height: 30),
            
            const Text("Create Your App ID", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            const Text("Enter your phone number. This will be used by your emergency contacts to connect with you.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 20),
            
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: "e.g. +923001234567",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                prefixIcon: const Icon(Icons.phone),
              ),
            ),
            const SizedBox(height: 20),
            
            ElevatedButton(
              onPressed: _loginWithoutOTP,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE53935),
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("Save & Continue", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}