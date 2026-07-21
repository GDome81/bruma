/// Configurazione dell'app, iniettata a build-time via `--dart-define`
/// (o `--dart-define-from-file=bruma.env.json`).
///
/// Esempio:
///   flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=eyJh...
class AppConfig {
  static const String supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');

  /// Bucket Storage per le foto cifrate (deve combaciare con la migration SQL).
  static const String photosBucket = 'photos';

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static String get missingConfigMessage =>
      'Configurazione Supabase mancante.\n\n'
      'Avvia l\'app passando le chiavi, ad esempio:\n\n'
      'flutter run \\\n'
      '  --dart-define=SUPABASE_URL=https://<ref>.supabase.co \\\n'
      '  --dart-define=SUPABASE_ANON_KEY=<anon-key>\n\n'
      'Oppure usa: flutter run --dart-define-from-file=bruma.env.json';
}
