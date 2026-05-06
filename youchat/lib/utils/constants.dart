/// Server connection constants
class AppConstants {
  // Change these to your server's IP/domain
  static const String serverUrl = 'https://itzel-fingered-lavina.ngrok-free.dev';
  static const String wsUrl = 'wss://itzel-fingered-lavina.ngrok-free.dev';

  // API endpoints
  static const String apiBase = '$serverUrl/api';
  static const String authRegister = '$apiBase/auth/register';
  static const String authLogin = '$apiBase/auth/login';
  static const String usersSearch = '$apiBase/users/search';
  static const String usersMe = '$apiBase/users/me';
  static const String usersProfile = '$apiBase/users/profile';
  static const String keysBundle = '$apiBase/keys/bundle';
  static const String keysCount = '$apiBase/keys/count';
  static const String groupsBase = '$apiBase/groups';
  static const String mediaUpload = '$apiBase/media/upload';

  // Deletion timer
  static const int deleteTimerSeconds = 15;
  static const int messageOfflineTtlSeconds = 60;

  // Pre-key batch size
  static const int preKeyBatchSize = 100;

  // Secure storage keys
  static const String storageTokenKey = 'auth_token';
  static const String storageUserIdKey = 'user_id';
  static const String storageIdentityKeyPair = 'identity_key_pair';
  static const String storageRegistrationId = 'registration_id';
  static const String storageSignedPreKey = 'signed_pre_key';
  static const String storagePrefix = 'youchat_';
}
