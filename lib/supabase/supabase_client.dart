import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/app_constants.dart';

/// Single entry point for Supabase. Only the publishable (anon) key ever ships
/// in the app — tenant isolation is enforced by RLS on the database.
abstract final class SupabaseService {
  static Future<void> initialize() async {
    final url = dotenv.env[AppConstants.envSupabaseUrl];
    final publishableKey = dotenv.env[AppConstants.envSupabasePublishableKey];

    if (url == null ||
        url.isEmpty ||
        publishableKey == null ||
        publishableKey.isEmpty) {
      throw StateError(
        'Missing ${AppConstants.envSupabaseUrl} or '
        '${AppConstants.envSupabasePublishableKey} in .env',
      );
    }

    await Supabase.initialize(url: url, publishableKey: publishableKey);
  }

  static SupabaseClient get client => Supabase.instance.client;
  static GoTrueClient get auth => client.auth;
}

final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => SupabaseService.client,
);
