/// Returns whether [value] contains URL parts that should not be persisted as
/// browser cache keys.
///
/// The browser model cache stores request URLs in CacheStorage. Plain catalog
/// flags such as Hugging Face's `?download=true` are safe to persist, but
/// user info, fragments, and credential-like query keys can leak signed or
/// session-specific material into durable browser storage.
bool hasPersistentCacheSensitiveUrlParts(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty) {
    return false;
  }
  if (uri.userInfo.isNotEmpty || uri.fragment.isNotEmpty) {
    return true;
  }

  return uri.queryParameters.keys.any((key) {
    final lower = key.toLowerCase();
    if (_benignPersistentQueryKeys.contains(lower)) {
      return false;
    }
    if (_sensitivePersistentQueryKeys.contains(lower) ||
        _sensitivePersistentQueryPrefixes.any(lower.startsWith)) {
      return true;
    }
    final segments = lower.split(RegExp(r'[._-]+'));
    return segments.any(_sensitivePersistentQueryKeySegments.contains);
  });
}

const _benignPersistentQueryKeys = {'download'};

const _sensitivePersistentQueryKeys = {
  'apikey',
  'authorization',
  'awsaccesskeyid',
  'credential',
  'expires',
  'key',
  'key-pair-id',
  'policy',
  'secret',
  'session',
  'sessionid',
  'sig',
  'signature',
  'token',
};

const _sensitivePersistentQueryKeySegments = {
  'auth',
  'credential',
  'key',
  'secret',
  'session',
  'sig',
  'signature',
  'token',
};

const _sensitivePersistentQueryPrefixes = {'x-amz', 'x-goog'};
