import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:kelime_mayinlari/screens/game_entry_screen.dart';

import 'game_screen.dart';

class ActiveGamesScreen extends StatelessWidget {
  const ActiveGamesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      return const Center(child: Text("Giriş yapılmamış."));
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("🎮 Oyunlarım"),
          bottom: const TabBar(
            tabs: [
              Tab(text: "📌 Aktif"),
              Tab(text: "✅ Biten"),
            ],
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: TabBarView(
                children: [
                  GameListWidget(
                    query: FirebaseFirestore.instance
                        .collection('games')
                        .where('gameOver', isEqualTo: false),
                    uid: uid,
                    emptyMessage: "Aktif oyun yok.",
                  ),
                  GameListWidget(
                    query: FirebaseFirestore.instance
                        .collection('games')
                        .where('gameOver', isEqualTo: true),
                    uid: uid,
                    emptyMessage: "Biten oyun yok.",
                  ),
                ],
              ),

            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => const GameEntryScreen()),
                        (route) => false,
                  );
                },
                icon: const Icon(Icons.arrow_back),
                label: const Text("Geri Dön"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),

          ],
        ),
      ),
    );

  }
}

class GameListWidget extends StatelessWidget {
  final Query query;
  final String uid;
  final String emptyMessage;

  const GameListWidget({
    super.key,
    required this.query,
    required this.uid,
    required this.emptyMessage,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: query.snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

        final games = snapshot.data!.docs.where((doc) =>
        doc['player1'] == uid || doc['player2'] == uid).toList();

        if (games.isEmpty) {
          return Center(child: Text(emptyMessage));
        }

        return ListView.builder(
          itemCount: games.length,
          itemBuilder: (context, index) {
            final game = games[index];
            final opponentName = game['player1'] == uid
                ? game['player2Username']
                : game['player1Username'];
            final duration = game['duration'];

            final isPlayer1 = game['player1'] == uid;
            final myScore = isPlayer1 ? game['player1Score'] : game['player2Score'];
            final opponentScore = isPlayer1 ? game['player2Score'] : game['player1Score'];
            final isGameOver = game['status'] == 'ended';
            final isWinner = game['winner'] == uid;

            return ListTile(
              tileColor: Colors.black12,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              title: Text(
                "Rakip: $opponentName",
                style: const TextStyle(color: Colors.white),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Süre: ${duration >= 60 ? '${(duration / 60).round()} saat' : '$duration dakika'}",
                      style: const TextStyle(color: Colors.white70)),
                  Text("Sen: $myScore - Rakip: $opponentScore",
                      style: const TextStyle(color: Colors.white70)),
                ],
              ),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isGameOver
                        ? (isWinner ? Icons.check_circle : Icons.cancel)
                        : Icons.hourglass_bottom, // Devam eden oyun için saat ikonu
                    color: isGameOver
                        ? (isWinner ? Colors.green : Colors.redAccent)
                        : Colors.orangeAccent, // Devam eden oyun rengi
                    size: 24,
                  ),
                  Text(
                    isGameOver
                        ? (isWinner ? "Kazandın" : "Kaybettin")
                        : "Devam ediyor",
                    style: TextStyle(
                      color: isGameOver
                          ? (isWinner ? Colors.green : Colors.redAccent)
                          : Colors.orangeAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => GameScreen(gameId: game.id),
                  ),
                );
              },
            );

          },
        );
      },
    );
  }
}