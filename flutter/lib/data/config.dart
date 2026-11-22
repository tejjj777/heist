class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
  );
  static const authRedirect = String.fromEnvironment('AUTH_REDIRECT_URL');
  static const aiUrl = String.fromEnvironment('AI_URL');
  static const visionUrl = String.fromEnvironment('VISION_URL');
  static bool get configured =>
      Uri.tryParse(supabaseUrl)?.scheme == 'https' && publishableKey.isNotEmpty;
}
