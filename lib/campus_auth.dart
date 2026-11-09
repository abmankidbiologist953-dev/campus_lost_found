import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'campus_database.dart';

abstract interface class CampusAuthGateway {
  bool get usesEmailForSignIn;

  Future<String> signIn({required String identifier, required String password});

  Future<void> signUp({
    required String password,
    required String matricNumber,
    required String email,
  });

  Future<void> sendPasswordResetEmail({required String email});
}

class FirebaseCampusAuthGateway implements CampusAuthGateway {
  final FirebaseAuth _firebaseAuth;

  FirebaseCampusAuthGateway({FirebaseAuth? firebaseAuth})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  @override
  bool get usesEmailForSignIn => true;

  @override
  Future<String> signIn({
    required String identifier,
    required String password,
  }) async {
    try {
      final credential = await _firebaseAuth.signInWithEmailAndPassword(
        email: identifier.trim(),
        password: password,
      );
      final accountMatricNumber = credential.user?.displayName?.trim();
      if (accountMatricNumber == null || accountMatricNumber.isEmpty) {
        await _firebaseAuth.signOut();
        throw StateError(
          'This account has no student profile. Create an account in the app '
          'or contact support.',
        );
      }
      return accountMatricNumber.toUpperCase();
    } on FirebaseAuthException catch (error) {
      throw StateError(_messageForAuth(error));
    }
  }

  @override
  Future<void> signUp({
    required String password,
    required String matricNumber,
    required String email,
  }) async {
    UserCredential credential;
    try {
      credential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (error) {
      throw StateError(_messageForAuth(error));
    }
    final user = credential.user;
    if (user == null) {
      throw StateError('Firebase did not return the new student account.');
    }
    try {
      await user.updateDisplayName(matricNumber.trim().toUpperCase());
    } on FirebaseAuthException catch (error) {
      await _removeUnregisteredUser(user);
      throw StateError(_messageForAuth(error));
    }
  }

  Future<void> _removeUnregisteredUser(User user) async {
    try {
      await user.delete();
    } on FirebaseAuthException catch (error) {
      debugPrint(
        'Could not remove the incomplete Firebase account: '
        '${_messageForAuth(error)}',
      );
    }
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {
    try {
      await _firebaseAuth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (error) {
      throw StateError(_messageForAuth(error));
    }
  }

  String _messageForAuth(FirebaseAuthException error) {
    switch (error.code) {
      case 'email-already-in-use':
        return 'An account already exists for this email address.';
      case 'invalid-email':
        return 'Enter a valid email address.';
      case 'weak-password':
        return 'Choose a stronger password.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect credentials';
      case 'user-disabled':
        return 'This account has been disabled. Contact support.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'operation-not-allowed':
        return 'Email and password sign-in is not enabled. Contact support.';
      case 'network-request-failed':
        return 'Could not reach the authentication service. Check your '
            'internet connection and try again.';
      default:
        return error.message ?? 'Authentication failed. Please try again.';
    }
  }
}

class LocalCampusAuthGateway implements CampusAuthGateway {
  @override
  bool get usesEmailForSignIn => false;

  @override
  Future<String> signIn({
    required String identifier,
    required String password,
  }) async {
    final normalizedMatricNumber = identifier.trim().toUpperCase();
    final isValid = await CampusDatabase.verifyPassword(
      normalizedMatricNumber,
      password,
    );
    if (!isValid) {
      throw StateError('Incorrect credentials');
    }
    return normalizedMatricNumber;
  }

  @override
  Future<void> signUp({
    required String password,
    required String matricNumber,
    required String email,
  }) async {
    final normalizedMatricNumber = matricNumber.trim().toUpperCase();
    if (await CampusDatabase.accountExists(normalizedMatricNumber)) {
      throw StateError('An account already exists for this matric number.');
    }
    await CampusDatabase.createAccount(normalizedMatricNumber, password);
  }

  @override
  Future<void> sendPasswordResetEmail({required String email}) async {
    throw StateError(
      'Password recovery is unavailable for local-only accounts.',
    );
  }
}
