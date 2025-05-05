import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:kelime_mayinlari/screens/game_entry_screen.dart';
import 'package:kelime_mayinlari/screens/welcome_screen.dart'; // yeni

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        } else if (snapshot.hasData) {
          return const GameEntryScreen();
        } else {
          return const WelcomeScreen(); // 🔁 giriş yapmamışsa artık buraya gidecek
        }
      },
    );
  }
}
