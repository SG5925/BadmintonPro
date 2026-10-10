import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'supabase/supabase_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Loads SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY from the bundled .env asset.
  await dotenv.load(fileName: '.env');

  await SupabaseService.initialize();

  runApp(const ProviderScope(child: BadmintonProApp()));
}
