import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../../models/user_model.dart';

final authServiceProvider = ChangeNotifierProvider<AuthService>((ref) {
  return AuthService();
});

class AuthService extends ChangeNotifier {
  UserModel? _currentUser;
  bool _isLoading = true;
  
  // Set to true to bypass Firebase for UI testing
  final bool _useMock = false; 

  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;

  AuthService() {
    _initAuth();
  }

  Future<void> _initAuth() async {
    // Both real devices and emulators will use real Firebase Auth
    // Use test phone numbers (+919137425943) to bypass reCAPTCHA and SMS quotas
    debugPrint('📱 Initializing real Firebase Auth');
    _checkAuth();
  }

  // ─── SharedPreferences keys ────────────────────────────────────────────────
  static const _kUserCache = 'cached_user_data';

  Future<void> _saveUserToCache(UserModel user) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kUserCache, jsonEncode(user.toMap()));
    } catch (e) {
      debugPrint('Cache save error: $e');
    }
  }

  Future<UserModel?> _loadUserFromCache(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kUserCache);
      if (raw != null) {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        if (map['uid'] == uid) {
          debugPrint('✅ Loaded user from cache');
          return UserModel.fromMap(map, uid);
        }
      }
    } catch (e) {
      debugPrint('Cache load error: $e');
    }
    return null;
  }

  void _checkAuth() {
    if (_useMock) {
      _isLoading = false;
      notifyListeners();
      return;
    }
    
    try {
      FirebaseAuth.instance.authStateChanges().listen((User? user) async {
        try {
          if (user != null) {
            // Try loading from cache first for instant UI
            final cached = await _loadUserFromCache(user.uid);
            if (cached != null && cached.name.isNotEmpty) {
              _currentUser = cached;
              _isLoading = false;
              notifyListeners();
            }

            // Then try Firestore for fresh data
            try {
              final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
              if (doc.exists) {
                final data = doc.data()!;
                _currentUser = UserModel(
                  uid: user.uid,
                  name: data['name'] ?? '',
                  email: data['email'] ?? '',
                  phoneNumber: data['phoneNumber'] ?? user.phoneNumber ?? '',
                  about: data['about'] ?? "Hey there! I am using ConnectCall.",
                  profileImageUrl: data['profileImageUrl'] ?? '',
                  isOnline: data['isOnline'] ?? true,
                  fcmToken: data['fcmToken'],
                );
                await _saveUserToCache(_currentUser!); // Save fresh data to cache
              } else if (cached != null && cached.name.isNotEmpty) {
                // Doc not in Firestore but we have cache — restore to Firestore
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .set(cached.toMap(), SetOptions(merge: true));
                _currentUser = cached;
              } else {
                _currentUser = UserModel(uid: user.uid, email: '', name: '', phoneNumber: user.phoneNumber ?? '');
              }
            } catch (fsError) {
              debugPrint('Firestore error, using cache: $fsError');
              // Firestore failed — keep cached data if available
              if (cached == null || cached.name.isEmpty) {
                _currentUser = UserModel(uid: user.uid, email: '', name: '', phoneNumber: user.phoneNumber ?? '');
              }
            }
            _updateFCMToken(user.uid);
          } else {
            _currentUser = null;
            // NOTE: We do NOT clear cache on logout so data is available on next login
          }
        } catch (e) {
          debugPrint('Auth Check Error: $e');
          if (user != null) {
            _currentUser = UserModel(uid: user.uid, email: '', name: '', phoneNumber: user.phoneNumber ?? '');
            _updateFCMToken(user.uid);
          } else {
            _currentUser = null;
          }
        } finally {
          _isLoading = false;
          notifyListeners();
        }
      });
    } catch (e) {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _updateFCMToken(String uid) async {
    try {
      await FirebaseMessaging.instance.requestPermission();
      String? token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'fcmToken': token,
        }, SetOptions(merge: true));
        
        if (_currentUser != null) {
          final data = _currentUser!.toMap();
          data['fcmToken'] = token;
          _currentUser = UserModel.fromMap(data, uid);
          notifyListeners();
        }
      }
      
      // Listen for token refresh
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) {
        FirebaseFirestore.instance.collection('users').doc(uid).set({
          'fcmToken': newToken,
        }, SetOptions(merge: true));
      });
    } catch (e) {
      debugPrint("FCM Token Error: $e");
    }
  }

  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required Function(String verificationId) codeSent,
    required Function(String error) verificationFailed,
  }) async {
    await FirebaseAuth.instance.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (PhoneAuthCredential credential) async {
        // Auto-resolution on Android
        try {
          await FirebaseAuth.instance.signInWithCredential(credential);
        } catch (e) {
          debugPrint("Auto-resolution failed: $e");
        }
      },
      verificationFailed: (FirebaseAuthException e) {
        verificationFailed(e.message ?? 'Verification failed');
      },
      codeSent: (String verificationId, int? resendToken) {
        codeSent(verificationId);
      },
      codeAutoRetrievalTimeout: (String verificationId) {},
    );
  }

  Future<bool> verifyOTP(String verificationId, String smsCode) async {
    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
      return true;
    } catch (e) {
      debugPrint("OTP Verification Error: $e");
      return false;
    }
  }
  Future<bool> signInWithEmailPassword(String email, String password) async {
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return true;
    } catch (e) {
      debugPrint("Email Sign In Error: $e");
      return false;
    }
  }

  Future<bool> signUpWithEmailPassword(String email, String password, {required String name}) async {
    try {
      final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      await cred.user?.updateDisplayName(name);
      return true;
    } catch (e) {
      debugPrint("Email Sign Up Error: $e");
      return false;
    }
  }

  Future<bool> setupProfile(String name, String about, {String? phoneNumber}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return false;

    try {
      final userModel = UserModel(
        uid: user.uid,
        name: name,
        email: user.email ?? '',
        phoneNumber: phoneNumber ?? user.phoneNumber ?? '',
        about: about,
      );
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(userModel.toMap(), SetOptions(merge: true));
      
      _currentUser = userModel;
      await _saveUserToCache(userModel); // Cache locally for persistence
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint("Profile Setup Error: $e");
      return false;
    }
  }

  Future<void> logout() async {
    if (_useMock) {
      _currentUser = null;
      notifyListeners();
      return;
    }
    await FirebaseAuth.instance.signOut();
  }

  Future<bool> updateProfileImage(String filePath) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _currentUser == null) return false;

    try {
      // Compress and convert image to base64
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      
      // Keep it as a base64 string
      String base64Image = "data:image/jpeg;base64,${base64Encode(bytes)}";

      // Update Firestore directly (using set with merge so it creates doc if it doesn't exist)
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'profileImageUrl': base64Image,
      }, SetOptions(merge: true));

      // Update local model
      _currentUser = UserModel(
        uid: _currentUser!.uid,
        name: _currentUser!.name,
        email: _currentUser!.email,
        phoneNumber: _currentUser!.phoneNumber,
        about: _currentUser!.about,
        profileImageUrl: base64Image,
        isOnline: _currentUser!.isOnline,
      );
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint("Error uploading image: $e");
      return false;
    }
  }

  Future<bool> removeProfileImage() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _currentUser == null) return false;

    try {
      // Update Firestore (using set with merge)
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'profileImageUrl': '',
      }, SetOptions(merge: true));

      // Update local model
      _currentUser = UserModel(
        uid: _currentUser!.uid,
        name: _currentUser!.name,
        email: _currentUser!.email,
        phoneNumber: _currentUser!.phoneNumber,
        about: _currentUser!.about,
        profileImageUrl: '',
        isOnline: _currentUser!.isOnline,
      );
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint("Error removing image: $e");
      return false;
    }
  }

  Future<bool> updateProfileDetails(String name, String phone, String about) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _currentUser == null) return false;

    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'name': name,
        'phoneNumber': phone,
        'about': about,
      }, SetOptions(merge: true));

      _currentUser = UserModel(
        uid: _currentUser!.uid,
        name: name,
        email: _currentUser!.email,
        phoneNumber: phone,
        about: about,
        profileImageUrl: _currentUser!.profileImageUrl,
        isOnline: _currentUser!.isOnline,
        fcmToken: _currentUser!.fcmToken,
      );
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint("Error updating profile: $e");
      return false;
    }
  }
}
