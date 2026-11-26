import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/local_event_store.dart';
import '../../domain/models.dart';
import '../../domain/team_profile.dart';
import '../../theme/crease_theme.dart';
import '../../widgets/crease_ui.dart';
import '../../widgets/glass_surface.dart';

/// Returns `true` when the user is signed into a real (non-anonymous) Crease account.
bool isSignedInAccount() => LocalEventStore.instance.isSignedInAccount;

/// Ensures the user is signed into a real Crease account before performing a
/// cloud or multi-device action (live links, Pass the Baton, tournaments,
/// team invites, cloud avatar).
///
/// Returns `true` immediately if already signed in, or after the user completes
/// Google / Email sign-in in the contextual bottom sheet.
Future<bool> requireSignedInAccount(
  BuildContext context, {
  required String title,
  required String subtitle,
  bool initialSignIn = false,
}) async {
  if (isSignedInAccount()) return true;
  final message = await showCreaseAuthSheet(
    context,
    initialSignIn: initialSignIn,
    title: title,
    subtitle: subtitle,
  );
  if (message != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
  return isSignedInAccount();
}

/// Opens the Crease Sign-In / Create-Account bottom sheet.
/// Returns a user-facing status message if sign-in/sign-up succeeded, or `null`
/// if dismissed.
Future<String?> showCreaseAuthSheet(
  BuildContext context, {
  bool initialSignIn = false,
  String? title,
  String? subtitle,
}) async {
  final emailCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  var isSignInMode = initialSignIn;
  var obscurePassword = true;
  var keepLocalGuestData = true;
  String? busyAction; // 'google' | 'email'
  String? errorText;

  // Inspect local guest data before opening so shared-phone users can opt out
  // of absorbing someone else's guest matches into their account.
  var guestMatchCount = 0;
  var guestTeamCount = 0;
  var guestTournamentCount = 0;
  if (!isSignedInAccount()) {
    final results = await Future.wait([
      LocalEventStore.instance.listMatches(),
      LocalEventStore.instance.listTeams(),
      LocalEventStore.instance.listTournaments(),
    ]);
    guestMatchCount =
        (results[0] as List<MatchConfig>).where((m) => !m.isDemo).length;
    guestTeamCount = (results[1] as List<TeamProfile>).length;
    guestTournamentCount = (results[2] as List).length;
  }
  if (!context.mounted) {
    emailCtrl.dispose();
    passCtrl.dispose();
    return null;
  }
  final hasLocalGuestData =
      guestMatchCount > 0 || guestTeamCount > 0 || guestTournamentCount > 0;
  final guestParts = <String>[
    if (guestMatchCount > 0)
      '$guestMatchCount ${guestMatchCount == 1 ? 'match' : 'matches'}',
    if (guestTeamCount > 0)
      '$guestTeamCount ${guestTeamCount == 1 ? 'team' : 'teams'}',
    if (guestTournamentCount > 0)
      '$guestTournamentCount ${guestTournamentCount == 1 ? 'tournament' : 'tournaments'}',
  ];
  final guestSummary = guestParts.join(' · ');

  final done = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final c = ctx.crease;
      return StatefulBuilder(
        builder: (ctx, setModalState) {
          final isBusy = busyAction != null;

          Future<void> continueWithGoogle() async {
            setModalState(() {
              busyAction = 'google';
              errorText = null;
            });
            try {
              const webClientId = String.fromEnvironment(
                'GOOGLE_WEB_CLIENT_ID',
                defaultValue:
                    '232733391231-5ua6le5ihsadi54892ugm10j71uqt6mm.apps.googleusercontent.com',
              );
              final googleSignIn = GoogleSignIn(
                serverClientId: webClientId,
                scopes: const ['email', 'profile'],
              );
              final googleUser = await googleSignIn.signIn();
              if (googleUser == null) {
                setModalState(() => busyAction = null);
                return;
              }
              final googleAuth = await googleUser.authentication;
              final idToken = googleAuth.idToken;
              final accessToken = googleAuth.accessToken;
              if (idToken == null) {
                setModalState(() {
                  errorText =
                      'Google sign-in didn\'t finish. Please try again or sign in with email.';
                  busyAction = null;
                });
                return;
              }

              final auth = Supabase.instance.client.auth;
              final prevUser = auth.currentUser;
              final prevGuestUid = (prevUser != null &&
                      (prevUser.email == null ||
                          prevUser.email!.trim().isEmpty))
                  ? prevUser.id
                  : null;

              await auth.signInWithIdToken(
                provider: OAuthProvider.google,
                idToken: idToken,
                accessToken: accessToken,
              );

              var savedGuestCount = 0;
              if (keepLocalGuestData) {
                final claimed = await LocalEventStore.instance
                    .claimGuestDataForSignedInUser(
                  previousGuestUid: prevGuestUid,
                );
                savedGuestCount = claimed.matchesSaved;
              } else {
                await LocalEventStore.instance.clearLocalUserDataOnSignOut();
              }
              final restored =
                  await LocalEventStore.instance.restoreAccountDataFromCloud();

              final currentProfile =
                  await LocalEventStore.instance.getUserProfile();
              final googleName = googleUser.displayName?.trim() ?? '';
              final googlePhoto = googleUser.photoUrl?.trim() ?? '';
              final needsName = currentProfile.displayName.trim().isEmpty &&
                  googleName.isNotEmpty;
              final needsPhoto = (currentProfile.avatarUrl == null ||
                      currentProfile.avatarUrl!.isEmpty) &&
                  googlePhoto.isNotEmpty;
              if (needsName || needsPhoto) {
                await LocalEventStore.instance.saveUserProfile(
                  currentProfile.copyWith(
                    displayName: needsName ? googleName : null,
                    avatarUrl: needsPhoto ? googlePhoto : null,
                  ),
                );
              }

              if (!ctx.mounted) return;
              final message = savedGuestCount > 0
                  ? 'Signed in as ${googleUser.email} · saved $savedGuestCount guest ${savedGuestCount == 1 ? 'match' : 'matches'}.'
                  : restored > 0
                      ? 'Signed in as ${googleUser.email} & restored $restored ${restored == 1 ? 'match' : 'matches'}.'
                      : 'Signed in as ${googleUser.email}';
              Navigator.of(ctx).pop(message);
            } on AuthException catch (e) {
              setModalState(() {
                errorText = e.message;
                busyAction = null;
              });
            } catch (_) {
              setModalState(() {
                errorText =
                    'Google sign-in didn\'t finish. Check your connection and try again, or use email.';
                busyAction = null;
              });
            }
          }

          Future<void> submitEmail() async {
            final email = emailCtrl.text.trim();
            final pass = passCtrl.text;
            if (!email.contains('@') || pass.length < 6) {
              setModalState(() {
                errorText = 'Enter a valid email and at least 6 characters.';
              });
              return;
            }
            setModalState(() {
              busyAction = 'email';
              errorText = null;
            });
            try {
              final auth = Supabase.instance.client.auth;
              if (isSignInMode) {
                final prevUser = auth.currentUser;
                final prevGuestUid = (prevUser != null &&
                        (prevUser.email == null ||
                            prevUser.email!.trim().isEmpty))
                    ? prevUser.id
                    : null;
                await auth.signInWithPassword(email: email, password: pass);
                var savedGuestCount = 0;
                if (keepLocalGuestData) {
                  final claimed = await LocalEventStore.instance
                      .claimGuestDataForSignedInUser(
                    previousGuestUid: prevGuestUid,
                  );
                  savedGuestCount = claimed.matchesSaved;
                } else {
                  await LocalEventStore.instance.clearLocalUserDataOnSignOut();
                }
                final restored = await LocalEventStore.instance
                    .restoreAccountDataFromCloud();
                if (!ctx.mounted) return;
                final message = savedGuestCount > 0
                    ? 'Signed in as $email · saved $savedGuestCount guest ${savedGuestCount == 1 ? 'match' : 'matches'}.'
                    : restored > 0
                        ? 'Signed in & restored $restored ${restored == 1 ? 'match' : 'matches'}.'
                        : 'Signed in as $email';
                Navigator.of(ctx).pop(message);
              } else {
                const redirect = 'crease://login-callback';
                final prevUser = auth.currentUser;
                if (prevUser == null || !prevUser.isAnonymous) {
                  await auth.signUp(
                    email: email,
                    password: pass,
                    emailRedirectTo: redirect,
                  );
                } else {
                  await auth.updateUser(
                    UserAttributes(email: email, password: pass),
                    emailRedirectTo: redirect,
                  );
                }
                await LocalEventStore.instance.syncAllPendingToSupabase();
                if (!ctx.mounted) return;
                Navigator.of(ctx).pop(
                  'Account created and backed up. Check $email if confirmation is enabled.',
                );
              }
            } on AuthException catch (e) {
              setModalState(() {
                errorText = e.message;
                busyAction = null;
              });
            } catch (_) {
              setModalState(() {
                errorText = 'Check your internet connection and try again.';
                busyAction = null;
              });
            }
          }

          final resolvedTitle = title ??
              (isSignInMode ? 'Sign in to Crease' : 'Create account');
          final resolvedSubtitle = subtitle ??
              (isSignInMode
                  ? 'Restore your backed-up teams, matches, and career stats.'
                  : 'Save your teams, matches, and stats to an account so you never lose them.');

          return PopScope(
            canPop: !isBusy,
            child: Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: GlassSurface(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(24)),
                fillColor: c.surfaceSheet,
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                resolvedTitle,
                                style: Theme.of(ctx).textTheme.titleLarge,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Close',
                              onPressed: isBusy
                                  ? null
                                  : () => Navigator.of(ctx).pop(),
                              icon: const Icon(Icons.close_rounded, size: 20),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          resolvedSubtitle,
                          style: Theme.of(ctx).textTheme.bodyMedium,
                        ),
                        if (hasLocalGuestData && isSignInMode) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                            decoration: BoxDecoration(
                              color: c.surfaceKey,
                              borderRadius: BorderRadius.circular(
                                CreaseRadius.control,
                              ),
                              border: Border.all(color: c.hairline),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Save $guestSummary to my account',
                                        style: Theme.of(ctx)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Turn off if someone else scored them on this phone',
                                        style: Theme.of(ctx)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              fontSize: 11,
                                              color: c.inkSecondary,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch.adaptive(
                                  value: keepLocalGuestData,
                                  activeTrackColor: c.pitchGreen,
                                  onChanged: isBusy
                                      ? null
                                      : (v) => setModalState(
                                            () => keepLocalGuestData = v,
                                          ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            side: BorderSide(color: c.hairline),
                            backgroundColor: c.surfaceGlass,
                            foregroundColor: c.inkPrimary,
                          ),
                          onPressed: isBusy ? null : continueWithGoogle,
                          child: busyAction == 'google'
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.pitchGreen,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    const Text('Signing in with Google…'),
                                  ],
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    GoogleGMark(size: 18),
                                    SizedBox(width: 10),
                                    Text('Continue with Google'),
                                  ],
                                ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            Expanded(child: Divider(color: c.hairlineSubtle)),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                'or use email',
                                style: Theme.of(ctx)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: c.inkSecondary),
                              ),
                            ),
                            Expanded(child: Divider(color: c.hairlineSubtle)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: emailCtrl,
                          enabled: !isBusy,
                          keyboardType: TextInputType.emailAddress,
                          autofillHints: const [AutofillHints.email],
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            hintText: 'you@example.com',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: passCtrl,
                          enabled: !isBusy,
                          obscureText: obscurePassword,
                          decoration: InputDecoration(
                            labelText: isSignInMode
                                ? 'Password'
                                : 'Create a password',
                            hintText: 'At least 6 characters',
                            suffixIcon: IconButton(
                              tooltip: obscurePassword
                                  ? 'Show password'
                                  : 'Hide password',
                              icon: Icon(
                                obscurePassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 20,
                              ),
                              onPressed: () => setModalState(
                                () => obscurePassword = !obscurePassword,
                              ),
                            ),
                          ),
                        ),
                        if (errorText != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            errorText!,
                            style: Theme.of(ctx)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: c.wicketRed),
                          ),
                        ],
                        const SizedBox(height: 18),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: c.pitchGreen,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(48),
                          ),
                          onPressed: isBusy ? null : submitEmail,
                          child: busyAction == 'email'
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: c.pitchGreen,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      isSignInMode
                                          ? 'Signing in…'
                                          : 'Creating account…',
                                    ),
                                  ],
                                )
                              : Text(
                                  isSignInMode ? 'Sign in' : 'Create account',
                                ),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: isBusy
                              ? null
                              : () => setModalState(() {
                                    isSignInMode = !isSignInMode;
                                    errorText = null;
                                  }),
                          child: Text(
                            isSignInMode
                                ? 'New to Crease? Create account'
                                : 'Already have an account? Sign in',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );

  Future<void>.delayed(const Duration(milliseconds: 500), () {
    emailCtrl.dispose();
    passCtrl.dispose();
  });
  return done;
}
