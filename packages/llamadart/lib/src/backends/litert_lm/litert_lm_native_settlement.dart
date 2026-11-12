/// Whether native resources can be torn down independently of a Dart result.
///
/// A rejected request can still have live callbacks. Only the native owner can
/// establish settlement; a timeout or an error message cannot establish it.
enum LiteRtLmNativeSettlement {
  /// No native operation or callback remains in flight.
  settled,

  /// Native work or callbacks have not yet completed.
  pending,

  /// Settlement could not be proved; retain the family until process exit.
  quarantined,
}
