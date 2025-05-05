import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:kelime_mayinlari/screens/game_entry_screen.dart';
import 'package:kelime_mayinlari/services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  String errorMessage = "";

  void _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    // 1. Kullanıcı adına göre e-posta getir
    final query = await FirebaseFirestore.instance
        .collection('users')
        .where('username', isEqualTo: username)
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      setState(() {
        errorMessage = "❌ Bu kullanıcı adına ait hesap bulunamadı.";
      });
      return;
    }

    final email = query.docs.first['email'];

    // 2. Firebase Auth ile giriş yap
    final user = await _authService.signInWithEmail(email, password);
    if (user != null) {
      setState(() {
        errorMessage = "";
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("🟢 Giriş başarılı!")),

      );

      Future.delayed(const Duration(milliseconds: 500), () {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const GameEntryScreen()),
        );
      });
    } else {
      setState(() {
        errorMessage = "❌ Giriş başarısız. Şifre yanlış olabilir.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2E),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                "Kelime Mayınları",
                style: TextStyle(
                  fontSize: 32,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 32),

              _customTextField(_usernameController, "Kullanıcı Adı", Icons.person),
              const SizedBox(height: 16),

              _customTextField(_passwordController, "Şifre", Icons.lock, isPassword: true),
              const SizedBox(height: 24),

              ElevatedButton(
                onPressed: _login,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.lightBlueAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text("Giriş Yap", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),

              const SizedBox(height: 16),
              if (errorMessage.isNotEmpty)
                Text(errorMessage, style: const TextStyle(color: Colors.redAccent)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _customTextField(TextEditingController controller, String hint, IconData icon,
      {bool isPassword = false}) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white10,
        prefixIcon: Icon(icon, color: Colors.white70),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white54),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.lightBlueAccent),
        ),
      ),
    );
  }
}
