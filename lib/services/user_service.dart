import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/user_model.dart';

final userServiceProvider = ChangeNotifierProvider<UserService>((ref) {
  return UserService();
});

class UserService extends ChangeNotifier {
  List<UserModel> _users = [];
  bool _isLoading = false;

  List<UserModel> get users => _users;
  bool get isLoading => _isLoading;

  UserService() {
    // Start listening when service is created
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) {
        _listenToContacts();
      } else {
        _users = [];
        notifyListeners();
      }
    });
  }

  void _listenToContacts() {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .collection('contacts')
        .snapshots()
        .listen((snapshot) async {
      List<UserModel> tempUsers = [];
      for (var doc in snapshot.docs) {
        final contactId = doc.id;
        final contactDoc = await FirebaseFirestore.instance.collection('users').doc(contactId).get();
        if (contactDoc.exists) {
          tempUsers.add(UserModel.fromMap(contactDoc.data()!, contactId));
        }
      }
      _users = tempUsers;
      notifyListeners();
    });
  }

  Future<void> fetchUsers() async {
    // Now handled by stream listener
  }

  Future<bool> addContactByPhone(String phone) async {
    _isLoading = true;
    notifyListeners();

    try {
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      if (currentUserId == null) return false;

      final query = await FirebaseFirestore.instance
          .collection('users')
          .where('phoneNumber', isEqualTo: phone)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final contactId = query.docs.first.id;

      if (contactId == currentUserId) {
        _isLoading = false;
        notifyListeners();
        return false; // Can't add yourself
      }

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .collection('contacts')
          .doc(contactId)
          .set({'addedAt': FieldValue.serverTimestamp()});

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint("Add contact error: $e");
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> deleteContact(String contactId) async {
    final currentUserId = FirebaseAuth.instance.currentUser?.uid;
    if (currentUserId == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .collection('contacts')
        .doc(contactId)
        .delete();
  }
}
