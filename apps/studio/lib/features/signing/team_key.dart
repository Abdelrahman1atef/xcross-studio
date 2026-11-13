import '../../src/cli/xcross_events.dart';

/// Studio signs only with an App Store Connect team key (runbook F18): no
/// Apple ID sign-in and no individual keys. Returns why signing can't run, or
/// null when a usable team key is saved. Also null while the saved sign-in is
/// still unknown, so nothing is blocked before it has been read.
String? teamKeyMissingReason(AuthStatusReport? saved) {
  if (saved == null) return null;
  final key = saved.apiKey;
  if (key == null || key.problem != null || !key.privateKeyFound) {
    return 'Sign in with an App Store Connect team key first (Signing).';
  }
  if (key.isIndividual) {
    return 'The saved key is an individual key. Signing needs a team key '
        '(Signing).';
  }
  return null;
}
