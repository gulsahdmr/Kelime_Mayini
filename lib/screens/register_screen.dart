import 'package:flutter/material.dart';
import 'package:kelime_mayinlari/services/auth_service.dart';
import 'package:kelime_mayinlari/screens/login_screen.dart';


class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  final _usernameController = TextEditingController();


  String errorMessage = "";
  bool isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  bool isValidPassword(String password) {
    return RegExp(r'^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)[a-zA-Z\d]{8,}$').hasMatch(password);
  }



  void _register() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();
    final username = _usernameController.text.trim().toLowerCase();


    if (username.length < 3) {
      setState(() {
        errorMessage = "Kullanıcı adı en az 3 karakter olmalı.";
      });
      return;
    }

    if (!isValidEmail(email)) {
      setState(() {
        errorMessage = "Geçerli bir e-posta adresi giriniz.";
      });
      return;
    }

    if (!isValidPassword(password)) {
      setState(() {
        errorMessage = "Şifre en az 8 karakter, büyük-küçük harf ve rakam içermelidir.";
      });
      return;
    }

    final user = await _authService.registerWithEmail(email, password, username);
    if (user != null) {
      setState(() {
        errorMessage = "";
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("🟢 Kayıt başarılı! Girişe yönlendiriliyor...")),
      );

      Future.delayed(const Duration(milliseconds: 500), () {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      });
    } else {
      setState(() {
        errorMessage = "❌ Kayıt başarısız. Kullanıcı adı alınmış olabilir.";
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
                  letterSpacing: 1.2,
                ),
              ),
              _customTextField(_usernameController, "Kullanıcı Adı", Icons.person),
              const SizedBox(height: 16),
              const SizedBox(height: 32),
              _customTextField(_emailController, "E-posta", Icons.email),
              const SizedBox(height: 16),
              _customTextField(_passwordController, "Şifre", Icons.lock, isPassword: true),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _register,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text(
                  "Kayıt Ol",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 16),
              if (errorMessage.isNotEmpty)
                Text(
                  errorMessage,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 14),
                ),
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
        fillColor: Colors.white12,
        prefixIcon: Icon(icon, color: Colors.white70),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white54),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Colors.orangeAccent),
        ),
      ),
    );
  }
}
