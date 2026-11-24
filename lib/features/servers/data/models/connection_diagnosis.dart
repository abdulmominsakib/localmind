/// Why a server connection test failed, so setup can tell a refused socket,
/// a denied permission, a timeout and a wrong service apart.
enum ConnectionFailureKind {
  /// No socket could be opened: wrong host or port, the server only listens
  /// on loopback, a firewall, or iOS Local Network access was denied.
  unreachable,

  /// The server accepted the connection but did not answer in time.
  timeout,

  /// TLS handshake or certificate problem.
  tls,

  /// The server answered 401/403.
  unauthorized,

  /// Every probed endpoint answered 404: the wrong server type, port or
  /// path prefix, or a proxy that doesn't forward the API routes.
  notFound,

  /// Any other non-200 response.
  unexpectedStatus,

  /// A hosted provider that requires an API key was given none.
  missingApiKey,
}

class ConnectionDiagnosis {
  const ConnectionDiagnosis._({
    required this.ok,
    this.failure,
    this.endpoint,
    this.statusCode,
    this.nativeApiUnavailable = false,
  });

  const ConnectionDiagnosis.success({
    String? endpoint,
    bool nativeApiUnavailable = false,
  }) : this._(
         ok: true,
         endpoint: endpoint,
         nativeApiUnavailable: nativeApiUnavailable,
       );

  const ConnectionDiagnosis.failure(
    ConnectionFailureKind failure, {
    String? endpoint,
    int? statusCode,
  }) : this._(
         ok: false,
         failure: failure,
         endpoint: endpoint,
         statusCode: statusCode,
       );

  final bool ok;
  final ConnectionFailureKind? failure;

  /// The endpoint that succeeded, or the one that produced [failure].
  final String? endpoint;
  final int? statusCode;

  /// LM Studio answered only on its OpenAI-compatible `/v1` routes. Chat uses
  /// the native `/api/v1/chat` route, so a proxy that serves only `/v1` will
  /// pass setup and then fail on the first message.
  final bool nativeApiUnavailable;
}
