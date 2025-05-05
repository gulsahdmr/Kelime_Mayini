import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:kelime_mayinlari/data/letter_pool.dart';
import 'active_games_screen.dart';

class GameScreen extends StatefulWidget {
  final String gameId;
  const GameScreen({super.key, required this.gameId});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final int gridSize = 15;
  List<String> playerLetters = [];
  bool isLoading = true;
  Set<String> validWords = {};
  String? selectedLetter;
  Map<String, String> placedLetters = {};
  Map<String, String> confirmedLetters = {};
  bool isMyTurn = false;
  Map<String, String> specialTiles = {};
  Map<String, String> specialTilesFromFirestore = {};
  Set<String> recentlyExplodedTiles = {};
  bool _surrenderInfoShown = false;
  int remainingSeconds = 0;
  Timer? moveTimer;
  DateTime? turnEndTime;
  bool isExtraTurnJokerActive = false;
  bool showZoneBlockButton = false;
  bool showLetterFreezeButton = false;
  bool showExtraTurnButton = false;


  bool gameOverShown = false;


  String positionKey(int row, int col) => "${row}_${col}";

  final List<List<String>> boardMap = [
    ["N", "N", "K3", "N", "N", "H2", "N", "N", "N", "H2", "N", "N", "K3", "N", "N"],
    ["N", "H3", "N", "N", "N", "N", "H2", "N", "H2", "N", "N", "N", "N", "H3", "N"],
    ["K3", "N", "N", "N", "N", "N", "N", "K2", "N", "N", "N", "N", "N", "N", "K3"],
    ["N", "N", "N", "K2", "N", "N", "N", "N", "N", "N", "N", "K2", "N", "N", "N"],
    ["N", "N", "N", "N", "H3", "N", "N", "N", "N", "N", "H3", "N", "N", "N", "N"],
    ["H2", "N", "N", "N", "N", "H2", "N", "N", "N", "H2", "N", "N", "N", "N", "H2"],
    ["N", "H2", "N", "N", "N", "N", "H2", "N", "H2", "N", "N", "N", "N", "H2", "N"],
    ["N", "N", "K2", "N", "N", "N", "N", "C", "N", "N", "N", "N", "K2", "N", "N"],
    ["N", "H2", "N", "N", "N", "N", "H2", "N", "H2", "N", "N", "N", "N", "H2", "N"],
    ["H2", "N", "N", "N", "N", "H2", "N", "N", "N", "H2", "N", "N", "N", "N", "H2"],
    ["N", "N", "N", "N", "H3", "N", "N", "N", "N", "N", "H3", "N", "N", "N", "N"],
    ["N", "N", "N", "K2", "N", "N", "N", "N", "N", "N", "N", "K2", "N", "N", "N"],
    ["K3", "N", "N", "N", "N", "N", "N", "K2", "N", "N", "N", "N", "N", "N", "K3"],
    ["N", "H3", "N", "N", "N", "N", "H2", "N", "H2", "N", "N", "N", "N", "H3", "N"],
    ["N", "N", "K3", "N", "N", "H2", "N", "N", "N", "H2", "N", "N", "K3", "N", "N"],
  ];
  String getOpponentId(Map<String, dynamic> data) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return data['player1'] == uid ? data['player2'] : data['player1'];
  }

  String getCellType(int row, int col) {
    String value = boardMap[row][col];
    if (value == "C") return "center";
    if (["H2", "H3", "K2", "K3"].contains(value)) return value;
    return "normal";
  }

  @override
  void initState() {
    super.initState();
    _loadOrGenerateLetters();
    _loadWordList();
    _listenToGameChanges();
    _loadSpecialTiles();
    _listenToRewardUpdates(); // 🔄 Firestore'dan ödül dinlemesi


  }
  @override
  void dispose() {
    moveTimer?.cancel();
    super.dispose();
  }
  void _listenToRewardUpdates() {
    FirebaseFirestore.instance
        .collection('games')
        .doc(widget.gameId)
        .snapshots()
        .listen((snapshot) {
      final data = snapshot.data();
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final isPlayer1 = data?['player1'] == uid;
      final rewards = List<String>.from(data?[isPlayer1 ? 'player1Rewards' : 'player2Rewards'] ?? []);

      setState(() {
        showZoneBlockButton = rewards.contains("ODUL_BOLGE_YASAGI");
        showLetterFreezeButton = rewards.contains("ODUL_HARF_YASAGI");
        showExtraTurnButton = rewards.contains("ODUL_EKSTRA_HAMLE");
      });
    });
  }

  Future<void> updateUserStats(String uid, bool won) async {
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    await userRef.set({
      'played': FieldValue.increment(1),
      'won': won ? FieldValue.increment(1) : FieldValue.increment(0),
    }, SetOptions(merge: true));
  }

  void startTurnCountdown(int playerTimeLeft, DateTime lastMoveAt) {
    moveTimer?.cancel();
    final endTime = lastMoveAt.add(Duration(seconds: playerTimeLeft));
    turnEndTime = endTime;

    moveTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final now = DateTime.now();
      final remaining = endTime.difference(now).inSeconds;

      if (remaining <= 0) {
        timer.cancel();
        handleTimeOut();
      } else {
        setState(() {
          remainingSeconds = remaining;
        });
      }
    });
  }

  Future<void> handleTimeOut() async {
    final gameRef = FirebaseFirestore.instance.collection('games').doc(widget.gameId);
    final gameDoc = await gameRef.get();
    final data = gameDoc.data();
    if (data == null) return;

    final uid = FirebaseAuth.instance.currentUser!.uid;


    if (data['gameOver'] == true) {
      return;
    }

    final opponentId = data['player1'] == uid ? data['player2'] : data['player1'];

    await gameRef.update({
      'gameOver': true,
      'status': 'ended',
      'winner': opponentId,
      'timeoutBy': uid,
      'endedBy': 'timeout',
      'lastMoveAt': FieldValue.serverTimestamp(),
    });

    if (!mounted) return;

    final isLoser = uid == data['currentTurn'];

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isLoser
              ? "⏰ Süreniz doldu! Oyunu kaybettiniz."
              : "🏆 Rakibinizin süresi doldu. Tebrikler, kazandınız!",
        ),
        backgroundColor: isLoser ? Colors.redAccent : Colors.green,
      ),
    );

    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ActiveGamesScreen()),
            (route) => false,
      );
    }
  }



  Future<void> _loadSpecialTiles() async {
    final doc = await FirebaseFirestore.instance.collection('games').doc(widget.gameId).get();
    final data = doc.data();
    if (data == null) return;

    final raw = data['specialTiles'] as Map<String, dynamic>?;

    if (raw != null) {
      setState(() {
        specialTiles = raw.map((key, value) => MapEntry(key, value.toString()));
      });
    }
  }
  void _listenToGameChanges() {
    FirebaseFirestore.instance
        .collection('games')
        .doc(widget.gameId)
        .snapshots()
        .listen((snapshot) {
      final data = snapshot.data();
      if (data == null) return;

      final confirmedData = Map<String, String>.from(
          data['confirmedLetters'] ?? {});
      final currentTurn = data['currentTurn'];
      specialTilesFromFirestore = Map<String, String>.from(data['specialTiles'] ?? {});

      setState(() {
        confirmedLetters = confirmedData;
        isMyTurn = currentTurn == FirebaseAuth.instance.currentUser!.uid;

        final uid = FirebaseAuth.instance.currentUser!.uid;
        final lastMoveAt = (data['lastMoveAt'] as Timestamp?)?.toDate();
        final durationInSeconds = (data['duration'] ?? 2) * 60; // 🕒 Süre ayarı doğrudan buradan

        if (currentTurn == uid && lastMoveAt != null) {
          startTurnCountdown(durationInSeconds, lastMoveAt); // ✅ Süre başlatılıyor
        } else {
          moveTimer?.cancel();
          remainingSeconds = 0;
        }
      });
    });
  }


  Future<void> _loadWordList() async {
    final content = await DefaultAssetBundle.of(context).loadString(
        "assets/turkce_kelime_listesi.txt");
    setState(() {
      validWords = content
          .split('\n')
          .map((word) => word.trim().toUpperCase())
          .where((word) => word.isNotEmpty)
          .toSet();
    });
  }

  Future<void> _loadOrGenerateLetters() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final gameDoc = await FirebaseFirestore.instance.collection('games').doc(
        widget.gameId).get();
    final data = gameDoc.data();
    if (data == null) return;

    final isPlayer1 = data['player1'] == uid;
    final letterField = isPlayer1 ? 'player1Letters' : 'player2Letters';

    if (data.containsKey(letterField)) {
      setState(() {
        playerLetters = List<String>.from(data[letterField]);
        isLoading = false;
      });
    } else {
      List<String> newLetters = generateRandomLetters(letterPool, 7);
      await FirebaseFirestore.instance.collection('games')
          .doc(widget.gameId)
          .update({
        letterField: newLetters,
      });
      setState(() {
        playerLetters = newLetters;
        isLoading = false;
      });
    }
    placedLetters = Map<String, String>.from(data['placedLetters'] ?? {});
    confirmedLetters = Map<String, String>.from(data['confirmedLetters'] ?? {});
  }

  Future<void> _confirmWord() async {

    final uid = FirebaseAuth.instance.currentUser!.uid;
    final gameDoc = await FirebaseFirestore.instance.collection('games').doc(
        widget.gameId).get();
    final data = gameDoc.data();
    if (data == null) return;

    final isPlayer1 = data['player1'] == uid;
    final String letterField = isPlayer1 ? 'player1Letters' : 'player2Letters';
    final isFirstMove = !(data['firstMoveDone'] ?? false);

    final formedWordsWithPositions = getAllFormedWordsWithPositions();

    // 🚫 Geçersiz ilk hamle kontrolü
    if (formedWordsWithPositions.isEmpty ||
        (isFirstMove && !placedLetters.containsKey("7_7"))) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("❗ Geçersiz kelime veya ortadaki kareyi içermiyor.")),
      );
      return;
    }

    // ❌ Geçersiz kelime varsa iptal
    for (final word in formedWordsWithPositions) {
      final wordStr = word.map((e) => e.letter.replaceAll('*', '')).join();
      if (!validWords.contains(wordStr)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ '$wordStr' geçersiz bir kelime.")),
        );
        return;
      }
    }

    // ✅ Geçerli kelimeler
    final validWordsStr = formedWordsWithPositions.map((e) =>
        e.map((l) => l.letter).join()).toList();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(
          "✅ '${validWordsStr.join(', ')}' geçerli kelime(ler)!")),
    );
    final specialTilesFromFirestore = Map<String, String>.from(data['specialTiles'] ?? {});

    // 🎁 ÖDÜL MAYINI KONTROLÜ
    final rewardField = isPlayer1 ? 'player1Rewards' : 'player2Rewards';
    List<String> currentRewards = List<String>.from(data[rewardField] ?? []);
    Set<String> earnedRewards = {};

    for (final word in formedWordsWithPositions) {
      for (final l in word) {
        final key = "${l.row}_${l.col}";
        final tile = specialTilesFromFirestore[key];

        if (tile != null && tile.startsWith("ODUL_")) {
          earnedRewards.add(tile);
        }
      }
    }

    if (earnedRewards.isNotEmpty) {
      currentRewards.addAll(earnedRewards);

      // 🎯 Sadece ödül kazanılan kareleri temizle
      for (final word in formedWordsWithPositions) {
        for (final l in word) {
          final key = "${l.row}_${l.col}";
          final tile = specialTilesFromFirestore[key];
          if (tile != null && tile.startsWith("ODUL_")) {
            specialTilesFromFirestore.remove(key);
          }
        }
      }

      await FirebaseFirestore.instance.collection('games')
          .doc(widget.gameId)
          .update({
        rewardField: currentRewards,
        'specialTiles': specialTilesFromFirestore,
      });

      for (final reward in earnedRewards) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("🎁 Ödül Kazandınız: $reward"),
            backgroundColor: Colors.lightGreen,
          ),
        );
      }
    }


    // 💣 MAYIN: Kelime İptali kontrolü
    for (final word in formedWordsWithPositions) {
      for (final l in word) {
        final key = "${l.row}_${l.col}";
        final tile = specialTilesFromFirestore[key];

        if (tile == "MAYIN_KELIME_IPTALI") {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("❌ Kelimeniz iptal edildi!"),
              backgroundColor: Colors.redAccent,
            ),
          );

          final nextTurn = isPlayer1 ? data['player2'] : data['player1'];

          // 🧊 Harf sabitlenir ama puan verilmez
          confirmedLetters.addAll(placedLetters);

          // 🔁 Yeni harf ver
          int usedCount = placedLetters.length;
          List<String> newLetters = generateRandomLetters(letterPool, usedCount);
          playerLetters.addAll(newLetters);

          await FirebaseFirestore.instance.collection('games')
              .doc(widget.gameId)
              .update({
            'placedLetters': {},
            'confirmedLetters': confirmedLetters,
            'firstMoveDone': true,
            'currentTurn': nextTurn,
            letterField: playerLetters, // 💡 Firestore'a da güncelle
          });

          setState(() {
            placedLetters.clear();
          });

          return;
        }
      }
    }
// 💣 MAYIN: Puan Bölünmesi kontrolü
    bool hasPuanBolmeMayini = false;
    for (final word in formedWordsWithPositions) {
      for (final l in word) {
        final key = "${l.row}_${l.col}";
        if (specialTilesFromFirestore[key] == "MAYIN_PUAN_BOLUMESI") {
          hasPuanBolmeMayini = true;
          break;
        }
      }
      if (hasPuanBolmeMayini) break;
    }
    bool isConnectedToExistingWord() {
      for (var entry in placedLetters.entries) {
        final row = int.parse(entry.key.split("_")[0]);
        final col = int.parse(entry.key.split("_")[1]);

        // Komşu hücreleri kontrol et
        final neighbors = [
          "${row-1}_${col}", // yukarı
          "${row+1}_${col}", // aşağı
          "${row}_${col-1}", // sol
          "${row}_${col+1}", // sağ
          "${row-1}_${col-1}", // sol üst çapraz
          "${row-1}_${col+1}", // sağ üst çapraz
          "${row+1}_${col-1}", // sol alt çapraz
          "${row+1}_${col+1}", // sağ alt çapraz
        ];

        for (var neighbor in neighbors) {
          if (confirmedLetters.containsKey(neighbor)) {
            return true; // bir komşu bulundu
          }
        }
      }
      return false; // hiç komşu bulunamadı
    }
    if (!isFirstMove && !isConnectedToExistingWord()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("❗ Yerleştirdiğiniz kelime mevcut harflerle bağlantılı olmalı."),
        ),
      );
      return; // işlemi iptal et
    }


    bool hasPuanTransferMayini = false;
    for (final word in formedWordsWithPositions) {
      for (final l in word) {
        final key = "${l.row}_${l.col}";
        if (specialTilesFromFirestore[key] == "MAYIN_PUAN_TRANSFERI") {
          hasPuanTransferMayini = true;
          break;
        }
      }
      if (hasPuanTransferMayini) break;
    }
    bool hasHarfKaybiMayini = false;
    for (final word in formedWordsWithPositions) {
      for (final l in word) {
        final key = "${l.row}_${l.col}";
        if (specialTilesFromFirestore[key] == "MAYIN_HARF_KAYBI") {
          hasHarfKaybiMayini = true;
          break;
        }
      }
      if (hasHarfKaybiMayini) break;
    }

    int usedCount = placedLetters.length;
    final nextTurn = isPlayer1 ? data['player2'] : data['player1'];
    int currentRemaining = data['remainingLetters'] ?? 100;
    int updatedRemaining;

    if (hasHarfKaybiMayini) {
      final eldeKalanHarfSayisi = playerLetters.length;
      final yeniHarfler = generateRandomLetters(letterPool, 7);

      playerLetters = [...yeniHarfler]; // tüm eldeki harfleri sıfırla ve yeni ver

      updatedRemaining = currentRemaining + eldeKalanHarfSayisi - 7;
      if (updatedRemaining < 0) updatedRemaining = 0;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("🔄 Harf Kaybı Mayını! $eldeKalanHarfSayisi harfiniz iade edildi, yeni 7 harf verildi."),
          backgroundColor: Colors.orangeAccent,
        ),
      );
    } else {
      // Normal durumda sadece kullanılan harf kadar yeni harf ver
      final newLetters = generateRandomLetters(letterPool, usedCount);
      playerLetters.addAll(newLetters);
      updatedRemaining = currentRemaining - usedCount;
      if (updatedRemaining < 0) updatedRemaining = 0;
    }

    bool hasHamleEngeliMayini = false;
    for (final word in formedWordsWithPositions) {
      for (final l in word) {
        final key = "${l.row}_${l.col}";
        if (specialTilesFromFirestore[key] == "MAYIN_HAMLE_ENGELI") {
          hasHamleEngeliMayini = true;
          break;
        }
      }
      if (hasHamleEngeliMayini) break;
    }

// ✅ 1. HAMLE ENGELİ MAYINI KARELERİNİ BUL
    Set<String> hamleEngeliKeys = {};
    for (final word in formedWordsWithPositions) {
      for (final l in word) {
        final key = "${l.row}_${l.col}";
        if (specialTilesFromFirestore[key] == "MAYIN_HAMLE_ENGELI") {
          hamleEngeliKeys.add(key);
        }
      }
    }
    // 🔢 Puan hesapla
    int totalScore = 0;
    for (var word in formedWordsWithPositions) {
      totalScore += calculateWordScore(word, hamleEngeliKeys);
    }
    if (hasHamleEngeliMayini && isMyTurn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("🚫 Hamle Engeli mayınına bastınız! Çarpanlar etkisiz."),
          backgroundColor: Colors.orange,
        ),
      );
    }



    if (hasPuanBolmeMayini) {
      int originalScore = totalScore;
      totalScore = (totalScore * 0.3).round(); // %30'a indir
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("💣 Puan bölünmesi mayınına denk geldiniz! $originalScore → $totalScore"),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
    if (hasPuanTransferMayini) {
      // Puanı rakibe aktar
      final rakipField = isPlayer1 ? 'player2Score' : 'player1Score';
      final rakipCurrent = data[rakipField] ?? 0;
      final newRakipScore = rakipCurrent + totalScore;
      totalScore = 0; // kendi puanı sıfırlanır

      await FirebaseFirestore.instance.collection('games')
          .doc(widget.gameId)
          .update({
        rakipField: newRakipScore,
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("💸 Puan Transferi mayınına bastınız! Puanınız rakibe aktarıldı."),
          backgroundColor: Colors.redAccent,
        ),
      );
    }


    final scoreField = isPlayer1 ? 'player1Score' : 'player2Score';
    final currentScore = data[scoreField] ?? 0;
    final updatedScore = currentScore + totalScore;

    print("💰 Hesaplanan skor: $totalScore → Toplam: $updatedScore");

    if (updatedRemaining < 0) updatedRemaining = 0;

    setState(() {
      confirmedLetters.addAll(placedLetters);
      placedLetters.clear();

    });

// 🔁 Her hamle sonrası süre sistemini sıfırla
    final durationInSeconds = (data['duration'] ?? 2) * 60; // süre dakikaysa, saniyeye çevir

    final myTimeField = isPlayer1 ? 'player1TimeLeft' : 'player2TimeLeft';
    final opponentTimeField = isPlayer1 ? 'player2TimeLeft' : 'player1TimeLeft';

    await FirebaseFirestore.instance.collection('games')
        .doc(widget.gameId)
        .update({
      'placedLetters': placedLetters,
      'confirmedLetters': confirmedLetters,
      letterField: playerLetters,
      'firstMoveDone': true,
      'currentTurn': isExtraTurnJokerActive ? uid : nextTurn,
      'remainingLetters': updatedRemaining,
      scoreField: updatedScore,
      myTimeField: isExtraTurnJokerActive ? durationInSeconds : 0,
      opponentTimeField: isExtraTurnJokerActive ? (data[opponentTimeField] ?? durationInSeconds) : durationInSeconds,
      'lastMoveAt': FieldValue.serverTimestamp(),
      'consecutivePassCount': 0,
      'lastPassBy': null,
      'lastAction': 'move',
    });
// ✅ Joker sıfırlamayı Firestore update sonrası yap
    setState(() {
      isExtraTurnJokerActive = false;
    });
  }

  bool getTempWordStatus() {
    final entries = placedLetters.entries.toList();
    if (entries.isEmpty) return false;

    List<int> rows = entries.map((e) => int.parse(e.key.split("_")[0]))
        .toList();
    List<int> cols = entries.map((e) => int.parse(e.key.split("_")[1]))
        .toList();

    bool sameRow = rows
        .toSet()
        .length == 1;
    bool sameCol = cols
        .toSet()
        .length == 1;

    if (!sameRow && !sameCol) return false;

    int fixed = sameRow ? rows.first : cols.first;
    List<int> range = (sameRow ? cols : rows)
      ..sort();

    String word = "";
    for (int i = range.first; i <= range.last; i++) {
      String key = sameRow ? "${fixed}_$i" : "${i}_$fixed";
      String harf = placedLetters[key] ?? confirmedLetters[key] ?? "";
      if (harf.isEmpty) return false;
      word += harf;
    }

    return word.length > 1 && validWords.contains(word);
  }

  List<List<PositionedLetter>> getAllFormedWordsWithPositions() {
    Set<String> visited = {};
    List<List<PositionedLetter>> result = [];

    for (final entry in placedLetters.entries) {
      final row = int.parse(entry.key.split('_')[0]);
      final col = int.parse(entry.key.split('_')[1]);

      // YATAY
      int startCol = col;
      while (startCol > 0 &&
          (placedLetters.containsKey("${row}_${startCol - 1}") ||
              confirmedLetters.containsKey("${row}_${startCol - 1}"))) {
        startCol--;
      }
      int endCol = col;
      while (endCol < gridSize - 1 &&
          (placedLetters.containsKey("${row}_${endCol + 1}") ||
              confirmedLetters.containsKey("${row}_${endCol + 1}"))) {
        endCol++;
      }

      String hKey = "H_${row}_$startCol-$endCol";
      if (!visited.contains(hKey)) {
        List<PositionedLetter> word = [];
        for (int c = startCol; c <= endCol; c++) {
          String key = "${row}_$c";
          String? letter = placedLetters[key] ?? confirmedLetters[key];
          if (letter != null) {
            word.add(PositionedLetter(row: row, col: c, letter: letter));
          }
        }
        if (word.length > 1) result.add(word);
        visited.add(hKey);
      }

      // DİKEY
      int startRow = row;
      while (startRow > 0 &&
          (placedLetters.containsKey("${startRow - 1}_$col") ||
              confirmedLetters.containsKey("${startRow - 1}_$col"))) {
        startRow--;
      }
      int endRow = row;
      while (endRow < gridSize - 1 &&
          (placedLetters.containsKey("${endRow + 1}_$col") ||
              confirmedLetters.containsKey("${endRow + 1}_$col"))) {
        endRow++;
      }

      String vKey = "V_${col}_$startRow-$endRow";
      if (!visited.contains(vKey)) {
        List<PositionedLetter> word = [];
        for (int r = startRow; r <= endRow; r++) {
          String key = "${r}_$col";
          String? letter = placedLetters[key] ?? confirmedLetters[key];
          if (letter != null) {
            word.add(PositionedLetter(row: r, col: col, letter: letter));
          }
        }
        if (word.length > 1) result.add(word);
        visited.add(vKey);
      }
    }

    return result;
  }


  Future<String?> getPlacedWord() async {
    final entries = placedLetters.entries.toList();
    if (entries.isEmpty) return null;

    List<int> rows = entries.map((e) => int.parse(e.key.split("_")[0]))
        .toList();
    List<int> cols = entries.map((e) => int.parse(e.key.split("_")[1]))
        .toList();

    bool sameRow = rows
        .toSet()
        .length == 1;
    bool sameCol = cols
        .toSet()
        .length == 1;

    if (!sameRow && !sameCol) return null;

    int fixed = sameRow ? rows.first : cols.first;
    List<int> range = (sameRow ? cols : rows)
      ..sort();

    // Genişletme başlat
    int start = range.first;
    int end = range.last;

    while ((sameRow
        ? confirmedLetters.containsKey("${fixed}_${start - 1}")
        : confirmedLetters.containsKey("${start - 1}_$fixed")) && start > 0) {
      start--;
    }
    while ((sameRow
        ? confirmedLetters.containsKey("${fixed}_${end + 1}")
        : confirmedLetters.containsKey("${end + 1}_$fixed")) &&
        end < gridSize - 1) {
      end++;
    }

    // Kelimeyi oluştur
    String word = "";
    for (int i = start; i <= end; i++) {
      String key = sameRow ? "${fixed}_$i" : "${i}_$fixed";
      String harf = placedLetters[key] ?? confirmedLetters[key] ?? "";
      if (harf.isEmpty) return null;
      word += harf;
    }


    // Oyun verisini al
    final gameDoc = await FirebaseFirestore.instance.collection('games').doc(
        widget.gameId).get();
    final data = gameDoc.data();
    final isFirstMove = !(data?['firstMoveDone'] ?? false);

    if (isFirstMove && !placedLetters.containsKey("7_7")) {
      return null;
    }


    // 🔸 İlk hamle değilse mevcut harflerden en az birine temas etmeli
    if (!isFirstMove) {
      bool touchesExisting = false;

      for (var entry in placedLetters.entries) {
        final row = int.parse(entry.key.split("_")[0]);
        final col = int.parse(entry.key.split("_")[1]);

        final neighbors = [
          "${row - 1}_$col",
          "${row + 1}_$col",
          "${row}_${col - 1}",
          "${row}_${col + 1}",
          "${row - 1}_${col - 1}",
          "${row - 1}_${col + 1}",
          "${row + 1}_${col - 1}",
          "${row + 1}_${col + 1}",
        ];

        for (final neighbor in neighbors) {
          if (confirmedLetters.containsKey(neighbor)) {
            touchesExisting = true;
            break;
          }
        }
        if (touchesExisting) break;
      }
      if (!touchesExisting) return null;
    }

    return word;
  }


  Widget _buildLetterRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: playerLetters.map((letter) {
            return GestureDetector(
              onTap: () {
                setState(() {
                  selectedLetter = letter;
                });
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(
                    vertical: 12, horizontal: 14),
                decoration: BoxDecoration(
                  color: selectedLetter == letter ? Colors.amber : Colors
                      .cyanAccent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(2, 2),
                    )
                  ],
                ),
                child: Text(
                  letter,
                  style: const TextStyle(fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.black),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget buildBoard() {
    final specialTiles = specialTilesFromFirestore ?? {};
    final screenWidth = MediaQuery.of(context).size.width;
    final double cellSize = screenWidth / gridSize;
    final allWords = getAllFormedWordsWithPositions();
    Set<String> greenBorderKeys = {};
    Set<String> redBorderKeys = {};
    Map<String, int> wordScoresByKey = {};

    for (final word in allWords) {
      final wordStr = word.map((e) => e.letter.replaceAll('*', '')).join();
      if (!validWords.contains(wordStr)) continue;

      final score = calculateWordScore(word.toList(), {}); // boş set göndererek hata giderilir
      final lastKey = positionKey(word.last.row, word.last.col);
      wordScoresByKey[lastKey] = score;
    }

    for (final word in allWords) {
      final wordStr = word.map((e) => e.letter.replaceAll('*', '')).join();
      final keys = word.map((e) => positionKey(e.row, e.col));

      if (word.length > 1) {
        final first = word.first;
        final last = word.last;

        final isHorizontal = first.row == last.row;
        final isVertical = first.col == last.col;

        //  Sadece yatay veya dikey kelimeleri kontrol et
        if (isHorizontal || isVertical) {
          if (validWords.contains(wordStr)) {
            greenBorderKeys.addAll(keys);
          } else {
            redBorderKeys.addAll(keys);
          }
        }
      }
    }


    return SizedBox(
      width: screenWidth,
      height: cellSize * gridSize,
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: gridSize,
          childAspectRatio: 1,
        ),
        itemCount: gridSize * gridSize,
        itemBuilder: (context, index) {
          final row = index ~/ gridSize;
          final col = index % gridSize;
          final key = positionKey(row, col);
          final cellType = getCellType(row, col);

          Color backgroundColor;
          switch (cellType) {
            case "H2": backgroundColor = Colors.blue[300]!; break;
            case "H3": backgroundColor = Colors.pink[300]!; break;
            case "K2": backgroundColor = Colors.green[300]!; break;
            case "K3": backgroundColor = Colors.orange[300]!; break;
            case "center": backgroundColor = Colors.amber[400]!; break;
            default: backgroundColor = Colors.grey[300]!;
          }

          final harf = confirmedLetters[key] ?? placedLetters[key];
          final baseHarf = harf?.replaceAll('*', '') ?? '';
          final puan = (harf != null && !harf.contains('*') &&
              letterPool.containsKey(baseHarf.toUpperCase()))
              ? letterPool[baseHarf.toUpperCase()]!['point'].toString()
              : '0';

          return GestureDetector(
            onTap: () async {
              if (!isMyTurn) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("⛔ Sıra sizde değil!")),
                );
                return;
              }

              if (confirmedLetters.containsKey(key)) return;

              if (placedLetters.containsKey(key)) {
                setState(() {
                  playerLetters.add(placedLetters[key]!);
                  placedLetters.remove(key);
                });
              } else if (selectedLetter != null) {
                if (selectedLetter == '*') {
                  final selected = await showJokerDialog();
                  if (selected != null) {
                    setState(() {
                      placedLetters[key] = '$selected*';
                      playerLetters.remove('*');
                    });
                  }
                } else {
                  setState(() {
                    placedLetters[key] = selectedLetter!;
                    playerLetters.remove(selectedLetter);
                    selectedLetter = null;
                  });
                }
              }
            },

            child: Container(
              width: cellSize,
              height: cellSize,
              margin: const EdgeInsets.all(0.5),
              decoration: BoxDecoration(
                color: recentlyExplodedTiles.contains(key)
                    ? Colors.red.withOpacity(0.5)
                    : harf != null ? Colors.yellow[200] : backgroundColor,
                border: Border.all(
                  color: greenBorderKeys.contains(key)
                      ? Colors.green
                      : redBorderKeys.contains(key)
                      ? Colors.red
                      : Colors.black12,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Text(
                      harf != null
                          ? harf.replaceAll('*', '')
                          : (cellType == "H2"
                          ? "H²"
                          : cellType == "H3"
                          ? "H³"
                          : cellType == "K2"
                          ? "K²"
                          : cellType == "K3"
                          ? "K³"
                          : cellType == "center"
                          ? "⭐"
                          : ""),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.brown[900],
                      ),
                    ),
                  ),
                  if (harf != null && puan != null)
                    Positioned(
                      top: 2,
                      right: 3,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.white70,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Text(
                          puan,
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  if (wordScoresByKey.containsKey(key))
                    Positioned(
                      bottom: 2,
                      right: 3,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          wordScoresByKey[key]!.toString(),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  if (recentlyExplodedTiles.contains(key))
                    const Center(
                      child: Icon(Icons.warning_amber_rounded, color: Colors.white, size: 28),
                    ),
                ],
              ),
            ),
          );

        },
      ),
    );
  }
  Future<String?> showJokerDialog() async {
    String? selected;
    await showDialog(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text("Joker Harf Seçimi"),
          content: SizedBox(
            width: double.maxFinite,
            child: Wrap(
              children: 'ABCÇDEFGĞHIİJKLMNOÖPRSŞTUÜVYZ'.split('').map((letter) {
                return Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: ElevatedButton(
                    child: Text(letter),
                    onPressed: () {
                      selected = letter;
                      Navigator.of(context).pop();
                    },
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
    return selected;
  }
  Widget buildHeader(Map<String, dynamic> data) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final isPlayer1 = data['player1'] == uid;
    final isMyTurn = data['currentTurn'] == uid;

    final myName = isPlayer1
        ? data['player1Username']
        : data['player2Username'];
    final myScore = isPlayer1 ? data['player1Score'] : data['player2Score'];
    final opponentName = isPlayer1
        ? data['player2Username']
        : data['player1Username'];
    final opponentScore = isPlayer1
        ? data['player2Score']
        : data['player1Score'];

    final currentTurnId = data['currentTurn'];
    final remainingLetters = data['remainingLetters'];

    return Container(
      color: Colors.black12,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Sol: Oyuncu bilgisi
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: currentTurnId == uid ? Colors.green[400] : Colors
                  .transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(myName, style: const TextStyle(color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
                Text("$myScore P",
                    style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),


          Column(
            children: [
              const Text("Kalan Harf", style: TextStyle(color: Colors.white70)),
              Text(
                remainingLetters.toString(),
                style: const TextStyle(color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold),
              ),
            ],
          ),
          // Sağ: Rakip bilgisi
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: currentTurnId != uid ? Colors.green[400] : Colors
                  .transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(opponentName, style: const TextStyle(color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
                Text("$opponentScore P",
                    style: const TextStyle(color: Colors.white70)),
              ],
            ),
          ),
        ],
      ),
    );
  }
  Future<void> _passTurn() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final gameRef = FirebaseFirestore.instance.collection('games').doc(widget.gameId);
    final gameDoc = await gameRef.get();
    final data = gameDoc.data();
    if (data == null) return;

    final isPlayer1 = data['player1'] == uid;
    final nextTurn = isPlayer1 ? data['player2'] : data['player1'];
    final durationInSeconds = (data['duration'] ?? 2) * 60;

    final previousPassBy = data['lastPassBy'];
    final passCount = data['consecutivePassCount'] ?? 0;

    if (previousPassBy != null && previousPassBy != uid && passCount == 1) {
      final int player1Score = data['player1Score'] ?? 0;
      final int player2Score = data['player2Score'] ?? 0;
      final winner = player1Score > player2Score
          ? data['player1']
          : player2Score > player1Score
          ? data['player2']
          : null;

      await gameRef.update({
        'gameOver': true,
        'status': 'ended',
        'winner': winner,
        'endedBy': 'pass',
        'lastPassBy': uid,
        'consecutivePassCount': 2,
        'lastAction': 'pass',
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("🚫 Her iki oyuncu da pas geçti. Oyun bitti.")),
      );

      await Future.delayed(const Duration(seconds: 2));
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const ActiveGamesScreen()),
              (route) => false,
        );
      }
    } else {
      await gameRef.update({
        'currentTurn': nextTurn,
        'lastPassBy': uid,
        'consecutivePassCount': (previousPassBy == uid) ? 1 : 1,
        'lastMoveAt': FieldValue.serverTimestamp(),
        'lastAction': 'pass',
      });

      moveTimer?.cancel();
      setState(() {
        remainingSeconds = 0;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("⏭️ Pas geçildi. Sıra rakipte!")),
      );
    }
  }

  Future<void> _surrender() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final gameDoc = await FirebaseFirestore.instance
        .collection('games')
        .doc(widget.gameId)
        .get();
    final data = gameDoc.data();
    if (data == null) return;

    final winner = data['player1'] == uid ? data['player2'] : data['player1'];

    await FirebaseFirestore.instance.collection('games').doc(widget.gameId).update({
      'gameOver': true,
      'winner': winner,
      'status': 'ended',
      'lastSurrenderedBy': uid,
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("🏳️ Oyunu teslim ettiniz. Biten oyunlara taşındı."),
          backgroundColor: Colors.redAccent,
        ),
      );
      await Future.delayed(const Duration(seconds: 2));
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ActiveGamesScreen()),
            (route) => false,
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Oyun Ekranı"),
        backgroundColor: Colors.deepPurple,
        automaticallyImplyLeading: true,
      ),
      backgroundColor: const Color(0xFF1E1E2E),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('games')
            .doc(widget.gameId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;
          final uid = FirebaseAuth.instance.currentUser!.uid;
          final isGameOver = data['status'] == 'ended';
          final winnerId = data.containsKey('winner') ? data['winner'] : null;

          if (isGameOver && !_surrenderInfoShown) {
            _surrenderInfoShown = true;

            final player1Id = data['player1'];
            final player2Id = data['player2'];
            final actualWinner = data.containsKey('winner') ? data['winner'] : null;

            Future.microtask(() async {
              if (actualWinner != null) {
                await updateUserStats(actualWinner, true);
                final loser = actualWinner == player1Id ? player2Id : player1Id;
                await updateUserStats(loser, false);
              } else {
                await updateUserStats(player1Id, false);
                await updateUserStats(player2Id, false);
              }
            });

            final isWinner = uid == actualWinner;
            final isDraw = actualWinner == null;
            final isPlayer1 = data['player1'] == uid;
            final int myScore = isPlayer1 ? data['player1Score'] ?? 0 : data['player2Score'] ?? 0;
            final int opponentScore = isPlayer1 ? data['player2Score'] ?? 0 : data['player1Score'] ?? 0;
            final int remaining = data['remainingLetters'] ?? 0;
            final endedBy = data['endedBy'] ?? 'normal';

            WidgetsBinding.instance.addPostFrameCallback((_) {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text("🏁 Oyun Bitti"),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(isDraw
                          ? "🤝 Oyun berabere bitti."
                          : isWinner
                          ? "🎉 Tebrikler, oyunu kazandınız!"
                          : "😢 Oyunu kaybettiniz."),
                      const SizedBox(height: 10),
                      Text("🧮 Toplam Puan: $myScore"),
                      Text("🤖 Rakip Puanı: $opponentScore"),
                      Text("🧩 Kalan Harf: $remaining"),
                      Text("💣 Bitiş Türü: ${endedBy == 'timeout' ? 'Süre doldu' : endedBy == 'pass' ? 'Arka arkaya pas' : endedBy == 'surrender' ? 'Teslimiyet' : 'Normal'}"),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const ActiveGamesScreen()),
                              (route) => false,
                        );
                      },
                      child: const Text("Geri Dön"),
                    ),
                  ],
                ),
              );
            });
          }

          return Column(
            children: [
              buildHeader(data),
              const SizedBox(height: 10),
              Text("Game ID: ${widget.gameId}", style: const TextStyle(color: Colors.white)),
              const SizedBox(height: 10),

              Text(
                isMyTurn ? "🎯 Sıra sizde!" : "⏳ Rakibinizi bekliyorsunuz...",
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),

              if (isMyTurn)
                Text(
                  "⏱ Kalan Süre: $remainingSeconds sn",
                  style: const TextStyle(color: Colors.orangeAccent, fontSize: 18),
                ),

              const SizedBox(height: 8),
              _buildLetterRow(),

              const SizedBox(height: 10),
              Expanded(child: ZoomableBoard(child: buildBoard())),

              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: isMyTurn ? _confirmWord : () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("⛔ Sıra sizde değil!")),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text("✅ Onayla", style: TextStyle(fontSize: 18, color: Colors.white)),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: isMyTurn ? _passTurn : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text("🚫 Pas Geç", style: TextStyle(color: Colors.white)),
                  ),
                  ElevatedButton(
                    onPressed: isMyTurn ? _surrender : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text("🏳️ Teslim Ol", style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),

              // 🔽 Ödül Butonları Buraya
              const SizedBox(height: 10),
              if (showZoneBlockButton && isMyTurn)
                ElevatedButton(
                  onPressed: _applyZoneBlock,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                  child: const Text("🟦 Bölge Yasağı", style: TextStyle(color: Colors.white)),
                ),
              if (showLetterFreezeButton && isMyTurn)
                ElevatedButton(
                  onPressed: _applyLetterFreeze,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                  child: const Text("🧊 Harf Dondurma", style: TextStyle(color: Colors.white)),
                ),
              if (showExtraTurnButton && isMyTurn)
                ElevatedButton(
                  onPressed: _activateExtraTurn,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
                  child: const Text("🔁 Ekstra Hamle", style: TextStyle(color: Colors.white)),
                ),

              const SizedBox(height: 20),
            ],
          );

        },
      ),
    );
  }
  void _applyZoneBlock() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final gameRef = FirebaseFirestore.instance.collection('games').doc(widget.gameId);
    final gameData = (await gameRef.get()).data();
    if (gameData == null) return;

    final opponentId = gameData['player1'] == uid ? gameData['player2'] : gameData['player1'];
    await gameRef.update({
      'zoneBlock.$opponentId': 'right', // sadece sağ tarafı serbest bırak
      'player1Rewards': FieldValue.arrayRemove(["ODUL_BOLGE_YASAGI"]),
      'player2Rewards': FieldValue.arrayRemove(["ODUL_BOLGE_YASAGI"]),
    });

    setState(() {
      showZoneBlockButton = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("🟦 Rakibin hamle alanı kısıtlandı!")),
    );
  }

  void _applyLetterFreeze() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final gameRef = FirebaseFirestore.instance.collection('games').doc(widget.gameId);
    final gameData = (await gameRef.get()).data();
    if (gameData == null) return;

    final isPlayer1 = gameData['player1'] == uid;
    final opponentLetters = List<String>.from(gameData[isPlayer1 ? 'player2Letters' : 'player1Letters']);
    final frozenIndexes = List<int>.generate(opponentLetters.length, (i) => i)..shuffle();
    final opponentId = isPlayer1 ? gameData['player2'] : gameData['player1'];

    await gameRef.update({
      'frozenLetterIndexes.$opponentId': frozenIndexes.take(2).toList(),
      'player1Rewards': FieldValue.arrayRemove(["ODUL_HARF_YASAGI"]),
      'player2Rewards': FieldValue.arrayRemove(["ODUL_HARF_YASAGI"]),
    });

    setState(() {
      showLetterFreezeButton = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("🧊 Rakibin 2 harfi donduruldu!")),
    );
  }

  Future<void> _activateExtraTurn() async {
    isExtraTurnJokerActive = true;
    setState(() {
      showExtraTurnButton = false;
    });
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final gameRef = FirebaseFirestore.instance.collection('games').doc(widget.gameId);
    final gameData = (await gameRef.get()).data();
    if (gameData == null) return;

    final isPlayer1 = gameData['player1'] == uid;
    final rewardsField = isPlayer1 ? 'player1Rewards' : 'player2Rewards';

    await gameRef.update({
      rewardsField: FieldValue.arrayRemove(["ODUL_EKSTRA_HAMLE"]),
    });


    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("🔁 Ekstra hamle hakkı aktif! Hamleni yap ve tekrar oynayacaksın.")),
    );
  }

  int calculateWordScore(List<PositionedLetter> letters, Set<String> hamleEngeliKeys) {
    int total = 0;
    int wordMultiplier = 1;

    for (final l in letters) {
      final key = "${l.row}_${l.col}";
      final cellType = getCellType(l.row, l.col);
      final isNewLetter = placedLetters.containsKey(key);
      final isJoker = l.letter.contains('*');
      final baseLetter = l.letter.replaceAll('*', '').toUpperCase();
      int letterScore = isJoker ? 0 : (letterPool[baseLetter]?['point'] ?? 0);

      if (isNewLetter && !hamleEngeliKeys.contains(key)) {
        if (cellType == "H2") {
          letterScore *= 2;
        } else if (cellType == "H3") {
          letterScore *= 3;
        } else if (cellType == "K2") {
          wordMultiplier *= 2;
        } else if (cellType == "K3") {
          wordMultiplier *= 3;
        }
      }

      total += letterScore;
    }

    return total * wordMultiplier;
  }


}
class PositionedLetter {
  final int row;
  final int col;
  final String letter;

  PositionedLetter({required this.row, required this.col, required this.letter});
}
class ZoomableBoard extends StatefulWidget {
  final Widget child;
  const ZoomableBoard({super.key, required this.child});

  @override
  State<ZoomableBoard> createState() => _ZoomableBoardState();
}

class _ZoomableBoardState extends State<ZoomableBoard> {
  final TransformationController _controller = TransformationController();
  double _currentScale = 1.0;
  final double _minScale = 1.0;
  final double _maxScale = 2.5;

  Offset? _tapPosition;

  void _handleDoubleTapDown(TapDownDetails details) {
    _tapPosition = details.localPosition;
  }

  void _handleDoubleTap() {
    if (_tapPosition == null) return;

    setState(() {
      if (_currentScale == _minScale) {
        final zoomPoint = _tapPosition!;
        final zoomFactor = _maxScale;

        // Matris oluştur, zoom yapılan nokta ortada kalsın
        final Matrix4 zoomed = Matrix4.identity()
          ..translate(-zoomPoint.dx * (zoomFactor - 1), -zoomPoint.dy * (zoomFactor - 1))
          ..scale(zoomFactor);

        _controller.value = zoomed;
        _currentScale = zoomFactor;
      } else {
        _controller.value = Matrix4.identity();
        _currentScale = _minScale;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: _handleDoubleTapDown,
      onDoubleTap: _handleDoubleTap,
      child: InteractiveViewer(
        transformationController: _controller,
        panEnabled: true,
        scaleEnabled: false,
        constrained: false,
        child: widget.child,
      ),
    );
  }
}
