class SupabaseConfig {
  static const supabaseUrl = 'https://sajzzwdoforindpqiseh.supabase.co';
  static const supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNhanp6d2RvZm9yaW5kcHFpc2VoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkwMDMxMTksImV4cCI6MjA5NDU3OTExOX0.m4rjhis25BLhCyxtGbp-_EdT__gsI7zBo6H_DJxaYi4';
  static const railwayBaseUrl =
      'https://whisper-api-staging-57c7rekzja-uc.a.run.app';
  // Set this to the value of API_SECRET env var on Railway
  static const apiSecret = String.fromEnvironment('API_SECRET', defaultValue: '');
}
