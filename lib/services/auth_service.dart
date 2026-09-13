import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    _checkAuth();
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
            final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
            if (doc.exists) {
              final data = doc.data()!;
              _currentUser = UserModel(
                uid: user.uid,
                name: (data['name']?.toString().isNotEmpty == true) ? data['name'] : (user.displayName ?? 'User'),
                email: (data['email']?.toString().isNotEmpty == true) ? data['email'] : (user.email ?? ''),
                phoneNumber: data['phoneNumber'] ?? '',
                about: data['about'] ?? "Hey there! I am using ConnectCall.",
                profileImageUrl: data['profileImageUrl'] ?? '',
                isOnline: data['isOnline'] ?? true,
                fcmToken: data['fcmToken'],
              );
              // Fetch and update FCM token
              _updateFCMToken(user.uid);
            } else {
              _currentUser = UserModel(uid: user.uid, email: user.email ?? '', name: user.displayName ?? 'User', phoneNumber: '');
              _updateFCMToken(user.uid);
            }
          } else {
            _currentUser = null;
          }
        } catch (e) {
          debugPrint('Auth Check Error: $e');
          // If Firestore fails (e.g. Permission Denied), fallback to basic auth info
          if (user != null) {
             _currentUser = UserModel(uid: user.uid, email: user.email ?? '', name: user.displayName ?? 'User', phoneNumber: '');
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

  Future<bool> login(String email, String password) async {
    if (_useMock) {
      _currentUser = UserModel(uid: 'mock_123', email: email, name: 'Mock User', phoneNumber: '1234567890');
      notifyListeners();
      return true;
    }
    
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
      // _checkAuth listener will handle setting _currentUser
      return true;
    } catch (e) {
      debugPrint(e.toString());
      return false;
    }
  }

  Future<bool> register(String name, String email, String phone, String password) async {
    if (_useMock) {
      _currentUser = UserModel(uid: 'mock_123', email: email, name: name, phoneNumber: phone);
      notifyListeners();
      return true;
    }
    
    try {
      UserCredential cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(email: email, password: password);
      await cred.user?.updateDisplayName(name);
      
      // Save user to Firestore
      final userModel = UserModel(
        uid: cred.user!.uid,
        name: name,
        email: email,
        phoneNumber: phone,
      );
      await FirebaseFirestore.instance.collection('users').doc(cred.user!.uid).set(userModel.toMap());
      
      return true;
    } catch (e) {
      debugPrint("Registration Error: ${e.toString()}");
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
