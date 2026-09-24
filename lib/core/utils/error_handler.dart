import 'package:firebase_auth/firebase_auth.dart';

class ErrorHandler {
  static String getUserFriendlyMessage(dynamic error) {
    if (error is FirebaseAuthException) {
      switch (error.code) {
        case 'user-not-found':
          return 'No user found with this email.';
        case 'wrong-password':
          return 'Incorrect password. Please try again.';
        case 'email-already-in-use':
          return 'An account already exists with this email.';
        case 'invalid-email':
          return 'Please enter a valid email address.';
        case 'weak-password':
          return 'Your password is too weak.';
        case 'network-request-failed':
          return 'Network error. Please check your internet connection.';
        default:
          return 'Authentication failed: ${error.message}';
      }
    } else if (error is FirebaseException) {
      switch (error.code) {
        case 'unavailable':
          return 'Service temporarily unavailable. Please check your connection.';
        case 'permission-denied':
          return 'You do not have permission to perform this action.';
        default:
          return 'Server error occurred. Please try again later.';
      }
    } else if (error is Exception) {
      return error.toString().replaceAll('Exception: ', '');
    } else {
      return 'An unexpected error occurred. Please try again.';
    }
  }
}
