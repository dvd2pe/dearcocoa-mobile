import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Supabase integration for DearCocoa's social layer (community, groups,
/// events) and optional demo sign-in. The private journal stays local-first;
/// only social data touches the backend.
///
/// Demo credentials are intentionally prefilled per the client requirement:
/// "account pronti, con prefilled credentials con link per selezionare
/// accounts" — one tap signs in without typing anything.
class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  static const String defaultUrl =
      String.fromEnvironment('SUPABASE_URL',
          defaultValue: 'https://sukxerupxdctdnegghwa.supabase.co');
  static const String defaultAnonKey = String.fromEnvironment(
      'SUPABASE_PUBLISHABLE_KEY',
      defaultValue: 'sb_publishable_VgHxSnR6EfVVvWhO8iPrUA_JCvDIjV-');

  /// The five demo accounts shown on the login selection screen.
  static const List<DemoAccount> demoAccounts = [
    DemoAccount(
        email: 'sofia@dearcocoa.demo',
        password: 'Cocoa2026!',
        name: 'Sofia Rossi',
        avatarSeed: 'sofia'),
    DemoAccount(
        email: 'luca@dearcocoa.demo',
        password: 'Cocoa2026!',
        name: 'Luca Bianchi',
        avatarSeed: 'luca'),
    DemoAccount(
        email: 'giulia@dearcocoa.demo',
        password: 'Cocoa2026!',
        name: 'Giulia Ferrari',
        avatarSeed: 'giulia'),
    DemoAccount(
        email: 'marco@dearcocoa.demo',
        password: 'Cocoa2026!',
        name: 'Marco Conti',
        avatarSeed: 'marco'),
    DemoAccount(
        email: 'elena@dearcocoa.demo',
        password: 'Cocoa2026!',
        name: 'Elena Moretti',
        avatarSeed: 'elena'),
  ];

  bool _initialized = false;

  bool get isReady => _initialized;

  Future<void> init() async {
    if (_initialized) return;
    try {
      await Supabase.initialize(url: defaultUrl, anonKey: defaultAnonKey);
      _initialized = true;
    } catch (e) {
      debugPrint('Supabase init failed: $e');
    }
  }

  SupabaseClient get client {
    assert(_initialized, 'SupabaseService.init() must run before use');
    return Supabase.instance.client;
  }

  bool get isSignedIn =>
      _initialized && client.auth.currentSession != null;

  String? get currentUserId =>
      _initialized ? client.auth.currentUser?.id : null;

  /// One-tap demo sign-in.
  Future<AuthResponse> signInDemo(DemoAccount account) {
    return client.auth.signInWithPassword(
      email: account.email,
      password: account.password,
    );
  }

  Future<AuthResponse> signIn(String email, String password) {
    return client.auth.signInWithPassword(email: email, password: password);
  }

  Future<AuthResponse> signUp(String email, String password) {
    return client.auth.signUp(email: email, password: password);
  }

  /// Fetch the public profile row for the signed-in user, creating one when
  /// missing so a fresh demo account still yields a usable username.
  Future<Map<String, dynamic>?> fetchOwnProfile() async {
    final uid = currentUserId;
    if (uid == null) return null;
    try {
      final rows = await client
          .from('profiles')
          .select()
          .eq('id', uid)
          .limit(1)
          .maybeSingle();
      if (rows != null) return Map<String, dynamic>.from(rows);
    } catch (_) {}
    // Profile trigger may not exist yet (seed not run): derive from auth.
    final email = client.auth.currentUser?.email ?? '';
    final fallback =
        email.split('@').firstOrNull ?? demoAccounts.first.name;
    try {
      await client
          .from('profiles')
          .upsert({'id': uid, 'username': fallback});
    } catch (_) {}
    return {'id': uid, 'username': fallback};
  }

  Future<void> signOut() => client.auth.signOut();
}

class DemoAccount {
  const DemoAccount({
    required this.email,
    required this.password,
    required this.name,
    required this.avatarSeed,
  });

  final String email;
  final String password;
  final String name;
  final String avatarSeed;
}
