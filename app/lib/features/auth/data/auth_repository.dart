import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/core/config/app_constants.dart';
import 'package:prostuti/core/errors/failure.dart';
import 'package:prostuti/core/network/supabase_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Email + password authentication (Supabase Auth).
class AuthRepository {
  AuthRepository(this._auth);

  final GoTrueClient _auth;

  Session? get session => _auth.currentSession;

  Future<void> signIn({required String email, required String password}) async {
    try {
      await _auth.signInWithPassword(email: email.trim(), password: password);
    } on Object catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// Creates the account. `full_name` and `username` travel as user metadata;
  /// the `handle_new_user` trigger turns them into the profile row and grants
  /// the free trial.
  Future<bool> signUp({
    required String email,
    required String password,
    required String fullName,
    String? username,
    String locale = 'bn',
  }) async {
    try {
      final res = await _auth.signUp(
        email: email.trim(),
        password: password,
        emailRedirectTo: AppConstants.authRedirectUrl,
        data: {
          'full_name': fullName.trim(),
          'locale': locale,
          if (username != null && username.trim().isNotEmpty) 'username': username.trim().toLowerCase(),
        },
      );
      // With e-mail confirmation enabled there is no session until confirmed.
      return res.session != null;
    } on Object catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.resetPasswordForEmail(email.trim(), redirectTo: AppConstants.authRedirectUrl);
    } on Object catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<void> updatePassword(String password) async {
    try {
      await _auth.updateUser(UserAttributes(password: password));
    } on Object catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<void> signOut() => _auth.signOut();
}

final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepository(ref.watch(supabaseProvider).auth));
