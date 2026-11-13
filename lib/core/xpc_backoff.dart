/// Skips one XPC call site for 30s after its empty response; each site
/// keeps its own instance, so a failing call does not back off the others.
class XpcEmptyBackoff {
  // How long one call site stays backed off after an empty response.
  static const duration = Duration(seconds: 30);

  // Overridden in tests to move time without waiting.
  DateTime Function() clock = DateTime.now;

  DateTime? _until;

  bool get isBackedOff => _until != null && clock().isBefore(_until!);

  void noteSuccess() => _until = null;

  void noteEmptyResponse() => _until = clock().add(duration);
}
