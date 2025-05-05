import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'game_screen.dart';

class WaitingForMatchScreen extends StatefulWidget {
  final String requestId;
  const WaitingForMatchScreen({super.key, required this.requestId});

  @override
  State<WaitingForMatchScreen> createState() => _WaitingForMatchScreenState();
}

class _WaitingForMatchScreenState extends State<WaitingForMatchScreen> {
  @override
  void initState() {
    super.initState();
    _listenForMatch();
  }

  void _listenForMatch() {
    FirebaseFirestore.instance
        .collection('game_requests')
        .doc(widget.requestId)
        .snapshots()
        .listen((snapshot) {
      final data = snapshot.data();
      if (data != null && data['matched'] == true && data['gameId'] != null) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => GameScreen(gameId: data['gameId']),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2E),
      body: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 20),
            Text(
              "Eşleşme bekleniyor...",
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}