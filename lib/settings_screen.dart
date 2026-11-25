import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart'; // main.dart se themeNotifier aur colorNotifier access karne ke liye

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // 5 Professional Color Schemes
  final List<Color> _availableColors = [
    const Color(0xFFE53935), // Default Red
    const Color(0xFF1E88E5), // Blue
    const Color(0xFF43A047), // Green
    const Color(0xFF8E24AA), // Purple
    const Color(0xFFFFB300), // Amber
  ];

  void _toggleDarkMode(bool value) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDark', value);
    themeNotifier.value = value ? ThemeMode.dark : ThemeMode.light;
  }

  void _changeColor(Color color) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeColor', color.value);
    colorNotifier.value = color;
  }

  @override
  Widget build(BuildContext context) {
    bool isDark = themeNotifier.value == ThemeMode.dark;
    Color primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text("App Settings", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Dark Mode Toggle
          SwitchListTile(
            activeColor: primaryColor,
            title: const Text("Dark Mode", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            subtitle: const Text("Switch between light and dark themes"),
            value: isDark,
            onChanged: _toggleDarkMode,
            secondary: Icon(isDark ? Icons.dark_mode : Icons.light_mode, color: primaryColor, size: 30),
          ),
          
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Divider(),
          ),
          
          // Color Scheme Selector
          const Text("Select Color Scheme", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 15),
          Wrap(
            spacing: 15,
            children: _availableColors.map((color) {
              return GestureDetector(
                onTap: () => _changeColor(color),
                child: CircleAvatar(
                  backgroundColor: color,
                  radius: 25,
                  child: colorNotifier.value == color 
                      ? const Icon(Icons.check, color: Colors.white, size: 30) 
                      : null,
                ),
              );
            }).toList(),
          )
        ],
      ),
    );
  }
}