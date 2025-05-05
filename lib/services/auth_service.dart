import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
// kayıt ekrannı
  // Kayıt Fonksiyonu
  Future<User?> registerWithEmail(String email, String password, String username) async {
    try {
      // Kullanıcı adını normalize et (küçük harf + boşluk silme)
      final trimmedUsername = username.trim().toLowerCase();

      // Kullanıcı adı zaten var mı kontrol et
      final existing = await FirebaseFirestore.instance
          .collection('users')
          .where('username', isEqualTo: trimmedUsername)
          .get();

      if (existing.docs.isNotEmpty) {
        print("⚠️ Bu kullanıcı adı zaten kullanılıyor.");
        return null;
      }

      // Firebase Authentication ile kullanıcıyı oluştur
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      User? user = result.user;
      if (user == null) {
        print("⚠️ Kullanıcı oluşturulamadı.");
        return null;
      }

      // Firestore'a kullanıcı bilgilerini kaydet
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'username': trimmedUsername,
        'email': email,
        'played': 0,
        'won': 0,
      });

      print("✅ Kullanıcı başarıyla kaydedildi: ${user.uid}");
      return user;
    } catch (e, stackTrace) {
      print("🛑 Kayıt hatası: $e");
      print("STACK TRACE:\n$stackTrace");
      return null;
    }
  }



  // Giriş Yap
  Future<User?> signInWithEmail(String email, String password) async {
    try {
      UserCredential result =
      await _auth.signInWithEmailAndPassword(email: email, password: password);
      return result.user;
    } catch (e) {
      print("Giriş Hatası: $e");
      return null;
    }
  }

  // Çıkış Yap
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // Kullanıcıyı dinle
  Stream<User?> get userChanges => _auth.authStateChanges();
}
