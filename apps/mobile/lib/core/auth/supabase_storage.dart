import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Implémentation personnalisée de LocalStorage pour Supabase utilisant Hive.
/// Cela permet d'éviter les problèmes d'accès au Keychain (Secure Storage)
/// courants sur macOS et certains environnements de développement.
class SupabaseHiveStorage extends LocalStorage {
  static final SupabaseHiveStorage _instance = SupabaseHiveStorage._internal();
  factory SupabaseHiveStorage() => _instance;
  SupabaseHiveStorage._internal();

  Box<String>? _box;
  static const _key = 'supabase_session';
  static const _boxName = 'supabase_auth_persistence';

  @override
  Future<void> initialize() async {
    if (_box != null && _box!.isOpen) {
      debugPrint('SupabaseHiveStorage: Hive box "$_boxName" already open.');
      return;
    }

    debugPrint('SupabaseHiveStorage: Initializing Hive box "$_boxName"...');
    try {
      _box = await Hive.openBox<String>(_boxName);
      debugPrint(
          'SupabaseHiveStorage: Hive box initialized successfully. Keys: ${_box!.keys.toList()}');
      debugPrint('SupabaseHiveStorage: Box path: ${_box!.path}');
    } catch (e) {
      debugPrint('SupabaseHiveStorage ERROR: Failed to open Hive box: $e');
      rethrow;
    }
  }

  @override
  Future<String?> accessToken() async {
    if (_box == null) {
      debugPrint(
          'SupabaseHiveStorage WARNING: accessToken called before initialize(). Checking if box is open...');
      if (Hive.isBoxOpen(_boxName)) {
        _box = Hive.box<String>(_boxName);
      } else {
        debugPrint(
            'SupabaseHiveStorage ERROR: Box is NOT open. Returning null.');
        return null;
      }
    }

    final token = _box!.get(_key);
    debugPrint(
        'SupabaseHiveStorage: Getting accessToken. Found: ${token != null ? "Yes (length: ${token.length})" : "No (Keys: ${_box!.keys.toList()})"}');
    return token;
  }

  @override
  Future<bool> hasAccessToken() async {
    if (_box == null) {
      debugPrint(
          'SupabaseHiveStorage WARNING: hasAccessToken called before initialize(). Checking if box is open...');
      if (Hive.isBoxOpen(_boxName)) {
        _box = Hive.box<String>(_boxName);
      } else {
        debugPrint(
            'SupabaseHiveStorage ERROR: Box is NOT open. Returning false.');
        return false;
      }
    }

    final value = _box!.get(_key);
    final hasToken = value != null && value.isNotEmpty;
    debugPrint(
        'SupabaseHiveStorage: hasAccessToken? $hasToken. Value length: ${value?.length ?? 0}. Keys: ${_box!.keys.toList()}');
    return hasToken;
  }

  @override
  Future<void> persistSession(String session) async {
    if (_box == null) {
      debugPrint(
          'SupabaseHiveStorage: persistSession called without box. Opening...');
      _box = await Hive.openBox<String>(_boxName);
    }
    debugPrint(
        'SupabaseHiveStorage: Persisting session (length: ${session.length}).');
    debugPrint(
        'SupabaseHiveStorage: Data to persist: ${session.substring(0, 50)}...');
    await _box!.put(_key, session);
    // Force flush for stability
    await _box!.flush();
    debugPrint('SupabaseHiveStorage: Session persisted and flushed.');
  }

  @override
  Future<void> removePersistedSession() async {
    if (_box == null) {
      if (Hive.isBoxOpen(_boxName)) {
        _box = Hive.box<String>(_boxName);
      } else {
        debugPrint(
            'SupabaseHiveStorage: removePersistedSession called but box is not open.');
        return;
      }
    }
    debugPrint('SupabaseHiveStorage: Removing persisted session. TRACE:');
    debugPrint(StackTrace.current.toString());
    await _box!.delete(_key);
    await _box!.flush();
    debugPrint('SupabaseHiveStorage: Session removed and flushed.');
  }
}
