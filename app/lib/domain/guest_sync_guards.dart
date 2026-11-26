/// Reusable single-flight deduplicator so concurrent callers (e.g. cold-start
/// startup sync + immediate user action) share one in-flight Future instead of
/// spawning duplicate anonymous Supabase accounts.
class SingleFlight<T> {
  Future<T>? _inFlight;

  Future<T> run(Future<T> Function() action) async {
    final existing = _inFlight;
    if (existing != null) return existing;

    final future = action();
    _inFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlight, future)) {
        _inFlight = null;
      }
    }
  }
}

/// Counts of local SQLite records not yet confirmed synced to Supabase.
/// Includes unsynced 0-ball matches (`matches`) so they are never silently
/// dropped before sign-out or guest migration.
class UnsyncedLocalCounts {
  const UnsyncedLocalCounts({
    required this.teams,
    required this.tournaments,
    required this.matches,
    required this.ballEvents,
  });

  final int teams;
  final int tournaments;
  final int matches;
  final int ballEvents;

  bool get hasAny => teams > 0 || tournaments > 0 || matches > 0 || ballEvents > 0;

  @override
  String toString() =>
      'teams=$teams, tournaments=$tournaments, matches=$matches, balls=$ballEvents';
}

/// Enforces the strict non-destructive sign-out order:
/// 1. Back up all pending local data (throws if offline or unsynced).
/// 2. Best-effort Google sign-out.
/// 3. Cloud auth sign-out (throws if it fails — local data stays intact).
/// 4. Clear local SQLite ONLY after steps 1 and 3 both succeeded.
/// 5. Best-effort fresh anonymous session (never fails an already-completed sign-out).
class SafeSignOutCoordinator {
  SafeSignOutCoordinator._();

  static Future<void> execute({
    required Future<void> Function() backupPending,
    required Future<void> Function() signOutGoogle,
    required Future<void> Function() signOutCloud,
    required Future<void> Function() clearLocalData,
    required Future<void> Function() ensureFreshAnonymousSession,
  }) async {
    await backupPending();
    try {
      await signOutGoogle();
    } catch (_) {}
    await signOutCloud();
    await clearLocalData();
    try {
      await ensureFreshAnonymousSession();
    } catch (_) {}
  }
}

/// Persists `pending_guest_claim_uid` before invoking `claim_guest_data` and
/// clears it ONLY after the claim succeeds (or is no longer applicable), so a
/// transient network error at sign-in is automatically retried on next sync.
class PendingGuestClaimCoordinator {
  PendingGuestClaimCoordinator._();

  static Future<bool> run({
    required String? passedGuestUid,
    required String? currentUserId,
    required bool hasLocalData,
    required Future<String?> Function() readPendingGuestUid,
    required Future<void> Function(String? uid) writePendingGuestUid,
    required Future<void> Function(String guestUid, String newUid) runClaimRpc,
  }) async {
    final cleanPassed = passedGuestUid?.trim();
    if (cleanPassed != null && cleanPassed.isNotEmpty) {
      await writePendingGuestUid(cleanPassed);
    }
    final effectiveGuestUid =
        (cleanPassed != null && cleanPassed.isNotEmpty)
            ? cleanPassed
            : await readPendingGuestUid();

    if (!hasLocalData) {
      await writePendingGuestUid(null);
      return false;
    }

    if (currentUserId == null || currentUserId.isEmpty) {
      return false;
    }

    if (effectiveGuestUid == null ||
        effectiveGuestUid.isEmpty ||
        effectiveGuestUid == currentUserId) {
      await writePendingGuestUid(null);
      return false;
    }

    await runClaimRpc(effectiveGuestUid, currentUserId);
    await writePendingGuestUid(null);
    return true;
  }
}
