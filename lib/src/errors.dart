/// A sentinel error code reported by the Balíkobot client.
///
/// Every client failure maps to one of these codes so the caller can decide
/// whether a retry can succeed or the request is permanently refused.
enum BalikobotError {
  /// The arguments were rejected locally before any network call.
  invalidRequest,

  /// The provider permanently refused the request or the supplied data.
  rejected,

  /// The provider is temporarily unavailable, or the request never left the
  /// client.
  unavailable,

  /// The provider reported that the resource has no data yet.
  notFound,

  /// A mutating call may have reached the provider and its outcome is unknown.
  ambiguous,

  /// The provider answer violates the protocol.
  invalidResponse,
}

/// An exception carrying a [BalikobotError] code.
class BalikobotException implements Exception {
  /// Creates an exception with the given [code], an optional [message], and an
  /// optional [retryAfter] provider hint.
  const BalikobotException(this.code, [this.message = '', this.retryAfter]);

  /// The sentinel error code of this failure.
  final BalikobotError code;

  /// A human-readable description of the failure.
  final String message;

  /// The provider retry hint of a retryable failure, when one was sent.
  final Duration? retryAfter;

  /// Returns a string representation of this exception.
  @override
  String toString() => 'BalikobotException(${code.name}): $message';
}
