import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'config/constants.dart';
import 'core/auth/supabase_storage.dart';

import 'package:timeago/timeago.dart' as timeago;
import 'package:timeago/src/messages/fr_messages.dart' as fr_messages;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialiser timeago
  timeago.setLocaleMessages('fr', fr_messages.FrMessages());
  timeago.setLocaleMessages('fr_short', fr_messages.FrShortMessages());

  // Orientation portrait uniquement
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Status bar style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );

  // Initialiser Hive (storage local)
  await Hive.initFlutter();

  // Pré-ouvrir les boxes et vérifier leur contenu
  debugPrint('Main: Opening Hive boxes...');
  await Hive.openBox<dynamic>('settings');
  final authBox = await Hive.openBox<dynamic>('auth_prefs');
  final supabaseBox = await Hive.openBox<String>('supabase_auth_persistence');

  debugPrint('Main: Hive auth_prefs keys: ${authBox.keys.toList()}');
  debugPrint(
    'Main: Hive auth_prefs remember_me: ${authBox.get('remember_me')}',
  );
  debugPrint(
    'Main: Hive supabase_auth_persistence keys: ${supabaseBox.keys.toList()}',
  );
  if (supabaseBox.containsKey('supabase_session')) {
    final session = supabaseBox.get('supabase_session');
    debugPrint(
      'Main: Hive supabase_session found (length: ${session?.length})',
    );
  } else {
    debugPrint('Main: Hive supabase_session NOT FOUND in box.');
  }

  // Validation Supabase avant initialisation
  if (SupabaseConstants.url.isEmpty || SupabaseConstants.anonKey.isEmpty) {
    debugPrint('ERROR: Supabase URL or Anon Key is missing.');
    _runErrorApp(
      'Configuration Supabase manquante. Vérifiez vos paramètres --dart-define.',
    );
    return;
  }

  // Initialisation Analytics
  // Note: On le fait tôt pour choper le launch
  // Mais on a besoin de Dio qui est dans le container...
  // On va le faire via le provider plus tard ou ici si on instancie manuellement
  // Pour l'instant on laisse le provider s'en occuper au premier build de FacteurApp

  try {
    const url = SupabaseConstants.url;
    const key = SupabaseConstants.anonKey;

    // Initialiser Supabase avec timeout de sécurité
    debugPrint('Main: Initializing Supabase...');
    debugPrint('Main: Supabase URL: ${SupabaseConstants.url}');
    await Supabase.initialize(
      url: url,
      anonKey: key,
      authOptions: FlutterAuthClientOptions(
        localStorage: SupabaseHiveStorage(),
      ),
      headers: {
        'X-Client-Info': 'supabase-flutter/2.5.0',
      },
    ).timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        debugPrint(
            'Main: Supabase.initialize TIMEOUT - throwing to catch block');
        throw TimeoutException('Supabase.initialize timeout after 15 seconds');
      },
    );
    debugPrint('Main: Supabase initialized correctly.');
    final hasSession = Supabase.instance.client.auth.currentSession != null;
    debugPrint('Main: Supabase Session restored immediately: $hasSession');
  } catch (e) {
    debugPrint('ERROR: Failed to initialize Supabase: $e');
    _runErrorApp(
      'Erreur d\'initialisation Supabase. Vérifiez la validité de vos clés.',
    );
    return;
  }

  // Lancer l'app
  debugPrint('Main: Calling runApp...');
  runApp(const ProviderScope(child: FacteurApp()));
  debugPrint('Main: runApp called.');
}

void _runErrorApp(String message) {
  runApp(
    MaterialApp(
      home: Scaffold(
        backgroundColor: const Color(0xFF1A1A1A),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 64),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
