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

  /// Chiave PUBBLICA VAPID per le Web Push (non è segreta: sta nel client).
  /// La chiave PRIVATA corrispondente va SOLO nei secret della Edge Function.
  /// Sovrascrivibile a build-time con --dart-define=VAPID_PUBLIC_KEY=...
  static const String vapidPublicKey = String.fromEnvironment(
    'VAPID_PUBLIC_KEY',
    defaultValue:
        'BLaSx24EtYwcukwWWYfLZzQ5NMhY-dzcUgiKHpw2vkh8ko3OpUpFSqU5WZ_gj9N8Chl9-EAey2ACQEsc234WFdI',
  );

  /// Tag di build (impostato dalla CI via `--dart-define=BUILD_TAG=<sha>`).
  /// Serve a verificare quale versione è effettivamente in esecuzione.
  static const String buildTag =
      String.fromEnvironment('BUILD_TAG', defaultValue: 'dev');

  static String get shortBuild =>
      buildTag.length > 7 ? buildTag.substring(0, 7) : buildTag;

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
