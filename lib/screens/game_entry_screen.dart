import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:kelime_mayinlari/screens/waiting_for_match_screen.dart';
import 'package:kelime_mayinlari/screens/game_screen.dart';
import 'active_games_screen.dart';

class GameEntryScreen extends StatefulWidget {
  const GameEntryScreen({super.key});

  @override
  State<GameEntryScreen> createState() => _GameEntryScreenState();
}

class _GameEntryScreenState extends State<GameEntryScreen> {
  String username = "";
  int played = 0;
  int won = 0;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadUserData(); // geri gelindiğinde başarı oranını güncelle
  }


  Future<void> _loadUserData() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    if (userDoc.exists) {
      final data = userDoc.data();


      setState(() {
        username = data?['username'] ?? "";
        played = data?['played'] ?? 0;
        won = data?['won'] ?? 0;

      });
    }
  }
  Map<String, String> createSpecialTiles() {
    final random = Random();
    final Map<String, String> tiles = {};
    final List<String> types = [
      ...List.filled(5, "MAYIN_PUAN_BOLUMESI"),
      ...List.filled(4, "MAYIN_PUAN_TRANSFERI"),
      ...List.filled(3, "MAYIN_HARF_KAYBI"),
      ...List.filled(2, "MAYIN_HAMLE_ENGELI"),
      ...List.filled(2, "MAYIN_KELIME_IPTALI"),
      ...List.filled(2, "ODUL_EKSTRA_HAMLE"),
    ];

    while (types.isNotEmpty) {
      final row = random.nextInt(15);
      final col = random.nextInt(15);
      final key = "${row}_${col}";
      if (!tiles.containsKey(key)) {
        tiles[key] = types.removeLast();
      }
    }

    return tiles;
    }


  @override
  Widget build(BuildContext context) {
    double successRate = played == 0 ? 0 : (won / played) * 100;

    return Scaffold(
      backgroundColor: const Color(0xFF1E1E2E),
      appBar: AppBar(
        title: const Text("Ana Sayfa"),
        backgroundColor: Colors.deepPurple,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("👤 $username", style: const TextStyle(color: Colors.white, fontSize: 18)),
                Text("🎯 Başarı: ${successRate.toStringAsFixed(1)}%", style: const TextStyle(color: Colors.white70)),
              ],
            ),
            const SizedBox(height: 40),
            _menuButton(context, "🆕 Yeni Oyun", () => _showTimeOptions(context)),
            const SizedBox(height: 16),
            _menuButton(context, "📌 Oyunlarım", () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ActiveGamesScreen()));
            }),
          ],
        ),
      ),
    );
  }

  Widget _menuButton(BuildContext context, String text, VoidCallback onTap) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.teal,
        padding: const EdgeInsets.symmetric(vertical: 18),
        minimumSize: const Size(double.infinity, 60),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: Text(text, style: const TextStyle(fontSize: 18)),
    );
  }

  void _showTimeOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("🕒 Oyun Süresi Seç", style: TextStyle(fontSize: 20, color: Colors.white)),
              const SizedBox(height: 20),
              _timeOption(context, "⚡ Hızlı - 2 Dakika", Duration(minutes: 2)),
              _timeOption(context, "⚡ Hızlı - 5 Dakika", Duration(minutes: 5)),
              _timeOption(context, "🧠 Genişletilmiş - 12 Saat", Duration(hours: 12)),
              _timeOption(context, "🧠 Genişletilmiş - 24 Saat", Duration(hours: 24)),
            ],
          ),
        );
      },
    );
  }

  Widget _timeOption(BuildContext context, String title, Duration duration) {
    return ListTile(
      title: Text(title, style: const TextStyle(color: Colors.white)),
      onTap: () {
        Navigator.pop(context);
        _matchPlayer(context, duration);
      },
    );
  }

  void _matchPlayer(BuildContext context, Duration duration) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final uid = user.uid;
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final username = userDoc.data()?['username'] ?? 'Bilinmeyen';
    final durationInMinutes = duration.inMinutes;
    final gameRequests = FirebaseFirestore.instance.collection('game_requests');

    // ⛔ Önceden gönderilmiş ama eşleşmemiş bir istek var mı kontrol et
    final existingRequest = await gameRequests
        .where('userId', isEqualTo: uid)
        .where('matched', isEqualTo: false)
        .limit(1)
        .get();

    if (existingRequest.docs.isNotEmpty) {
      final existingRequestId = existingRequest.docs.first.id;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => WaitingForMatchScreen(requestId: existingRequestId),
        ),
      );
      return;
    }

    // 🎯 Rakip var mı kontrol et
    final query = await gameRequests
        .where('duration', isEqualTo: durationInMinutes)
        .where('matched', isEqualTo: false)
        .orderBy('createdAt')
        .get();

    QueryDocumentSnapshot? opponentDoc;
    try {
      opponentDoc = query.docs.firstWhere((doc) => doc['userId'] != uid);
    } catch (_) {
      opponentDoc = null;
    }

    if (opponentDoc != null) {
      final opponentId = opponentDoc['userId'];
      final opponentUsername = opponentDoc['username'];
      final random = Random();
      final currentTurn = random.nextBool() ? uid : opponentId;
      final durationInSeconds = durationInMinutes * 60;
      final newGame = await FirebaseFirestore.instance.collection('games').add({
        'player1': uid,
        'player1Username': username,
        'player2': opponentId,
        'player2Username': opponentUsername,
        'duration': durationInMinutes,
        'player1TimeLeft': durationInSeconds,
        'player2TimeLeft': durationInSeconds,
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'active',
        'player1Score': 0,
        'player2Score': 0,
        'remainingLetters': 86,
        'firstMoveDone': false,
        'currentTurn': currentTurn,
        'specialTiles': createSpecialTiles(),
        'lastPassBy': null,
        'consecutivePassCount': 0,
        'lastAction': 'move',
        'winner': null,
        'endedBy': null,
        'gameOver': false,
        'player1Rewards': [],
        'player2Rewards': [],
        'frozenLetterIndexes': {},
        'zoneBlock': {},


      });
      final usersRef = FirebaseFirestore.instance.collection('users');

// Oyuncu 1 (kendin) için güncelle
      await usersRef.doc(uid).set({
        'played': FieldValue.increment(0),
        'won': FieldValue.increment(0),
        'username': username,
      }, SetOptions(merge: true));

// Oyuncu 2 (rakip) için güncelle
      await usersRef.doc(opponentId).set({
        'played': FieldValue.increment(0),
        'won': FieldValue.increment(0),
        'username': opponentUsername,
      }, SetOptions(merge: true));


      await gameRequests.doc(opponentDoc.id).update({'matched': true, 'gameId': newGame.id});
      final ownRequest = await gameRequests.add({
        'userId': uid,
        'username': username,
        'duration': durationInMinutes,
        'createdAt': FieldValue.serverTimestamp(),
        'matched': true,
        'gameId': newGame.id,
      });

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => GameScreen(gameId: newGame.id)),
      );
    } else {
      final addedDoc = await gameRequests.add({
        'userId': uid,
        'username': username,
        'duration': durationInMinutes,
        'createdAt': FieldValue.serverTimestamp(),
        'matched': false,
      });

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => WaitingForMatchScreen(requestId: addedDoc.id),
        ),
      );
    }
  }
}