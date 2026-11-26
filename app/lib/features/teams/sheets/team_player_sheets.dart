part of '../teams_tab_view.dart';

extension _TeamDetailSheets on _TeamDetailScreenState {
  Future<void> _pickTeamLogo(ImageSource source) async {
    final ok = await requireSignedInAccount(
      context,
      title: 'Sign in to upload a team logo',
      subtitle: 'Team logos sync across devices, matches, and scorecards.',
    );
    if (!ok || !mounted) return;
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 82,
      );
      if (picked == null || !mounted) return;
      _setUploadingLogo(true);
      final bytes = await picked.readAsBytes();
      final url =
          await LocalEventStore.instance.uploadTeamLogo(_profile.id, bytes);
      if (!mounted) return;
      await _persist(_profile.copyWith(logoUrl: url));
      if (mounted) _setUploadingLogo(false);
    } catch (_) {
      if (!mounted) return;
      _setUploadingLogo(false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Could not upload team logo. Check connection and retry.'),
        ),
      );
    }
  }

  Future<void> _showTeamLogoOptions() async {
    final c = context.crease;
    final hasLogo =
        _profile.logoUrl != null && _profile.logoUrl!.trim().isNotEmpty;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return GlassSurface(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(CreaseRadius.sheet),
          ),
          fillColor: c.surfaceSheet,
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CreaseSheetHeader(title: '${_profile.name} logo'),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickTeamLogo(ImageSource.gallery);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Take photo'),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickTeamLogo(ImageSource.camera);
                },
              ),
              if (hasLogo)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.delete_outline_rounded,
                    color: c.wicketRed,
                  ),
                  title: Text(
                    'Remove logo',
                    style: TextStyle(color: c.wicketRed),
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _persist(_profile.copyWith(clearLogo: true));
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmUnlinkPlayer(
    String playerName, {
    bool isSelf = false,
  }) async {
    final target = _profile.playerByName(playerName);
    if (target == null) return;
    var isUnlinking = false;
    String? errorText;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final c = ctx.crease;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return PopScope(
              canPop: !isUnlinking,
              child: AlertDialog(
                title: Text(
                  isSelf
                      ? 'Unlink your account from $playerName?'
                      : 'Unlink $playerName?',
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isSelf
                          ? 'This releases your account from $playerName so you can claim the right player spot.'
                          : 'This removes the linked account from this player spot so the right teammate can claim it.',
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorText!,
                        style: TextStyle(fontSize: 12.5, color: c.wicketRed),
                      ),
                    ],
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: isUnlinking ? null : () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      disabledBackgroundColor:
                          isUnlinking ? c.pitchGreen : null,
                      disabledForegroundColor:
                          isUnlinking ? c.onPitchGreen : null,
                    ),
                    onPressed: isUnlinking
                        ? null
                        : () async {
                            setDialogState(() {
                              isUnlinking = true;
                              errorText = null;
                            });
                            try {
                              await LocalEventStore.instance
                                  .unlinkTeamPlayer(target.id);
                              await _loadClaimed();
                              if (ctx.mounted) Navigator.pop(ctx);
                            } catch (_) {
                              if (ctx.mounted) {
                                setDialogState(() {
                                  isUnlinking = false;
                                  errorText =
                                      'Could not unlink right now. Check connection and retry.';
                                });
                              }
                            }
                          },
                    child: isUnlinking
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: c.onPitchGreen,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text('Unlinking…'),
                            ],
                          )
                        : const Text('Unlink'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }


  Future<void> _editTeam() async {
    final otherTeams = await LocalEventStore.instance.listTeams();
    final otherNamesLower = otherTeams
        .where((t) => t.id != _profile.id)
        .map((t) => t.name.trim().toLowerCase())
        .toSet();
    if (!mounted) return;

    final nameCtrl = TextEditingController(text: _profile.name);
    final locCtrl = TextEditingController(text: _profile.location ?? '');
    String? errorText;
    final result = await showDialog<({String name, String? location})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          void submit() {
            final trimmed = nameCtrl.text.trim();
            if (trimmed.isEmpty) {
              setDialogState(() => errorText = 'Enter a team name.');
              return;
            }
            if (otherNamesLower.contains(trimmed.toLowerCase())) {
              setDialogState(
                () => errorText = 'You already have a team named "$trimmed".',
              );
              return;
            }
            final loc = locCtrl.text.trim();
            Navigator.pop(
              ctx,
              (name: trimmed, location: loc.isEmpty ? null : loc),
            );
          }

          return AlertDialog(
            title: const Text('Edit team'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Team name',
                    errorText: errorText,
                  ),
                  onChanged: (_) {
                    if (errorText != null) {
                      setDialogState(() => errorText = null);
                    }
                  },
                  onSubmitted: (_) => submit(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: locCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'City or area (optional)',
                    hintText: 'e.g. Lahore, Model Town',
                    prefixIcon: Icon(Icons.location_on_outlined, size: 19),
                  ),
                  onSubmitted: (_) => submit(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: submit,
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      nameCtrl.dispose();
      locCtrl.dispose();
    });
    if (result == null) return;
    await _persist(
      _profile.copyWith(
        name: result.name,
        location: result.location,
        clearLocation: result.location == null,
      ),
    );
  }

  Future<void> _confirmDeleteTeam() async {
    final c = context.crease;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${_profile.name}?'),
        content: const Text(
          'This removes the saved team, squad roles, and invite code. Past matches, scorecards, and player career stats will not be affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: c.wicketRed),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final deletedName = _profile.name;
    await LocalEventStore.instance.deleteTeam(_profile.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Deleted "$deletedName".')),
    );
    Navigator.of(context).pop();
  }

  Future<void> _confirmLeaveTeam() async {
    final c = context.crease;
    var isLeaving = false;
    String? errorText;

    final left = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return PopScope(
              canPop: !isLeaving,
              child: AlertDialog(
                title: Text('Leave ${_profile.name}?'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'This removes the team from your device and unlinks your spot. You can rejoin later with an invite code.',
                    ),
                    if (errorText != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        errorText!,
                        style: TextStyle(fontSize: 12.5, color: c.wicketRed),
                      ),
                    ],
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed:
                        isLeaving ? null : () => Navigator.pop(ctx, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: c.wicketRed,
                      disabledBackgroundColor: isLeaving ? c.wicketRed : null,
                      disabledForegroundColor:
                          isLeaving ? Colors.white : null,
                    ),
                    onPressed: isLeaving
                        ? null
                        : () async {
                            setDialogState(() {
                              isLeaving = true;
                              errorText = null;
                            });
                            try {
                              await LocalEventStore.instance
                                  .leaveTeam(_profile.id);
                              if (ctx.mounted) Navigator.pop(ctx, true);
                            } catch (_) {
                              if (ctx.mounted) {
                                setDialogState(() {
                                  isLeaving = false;
                                  errorText =
                                      'Could not leave right now. Check connection and retry.';
                                });
                              }
                            }
                          },
                    child: isLeaving
                        ? const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              ),
                              SizedBox(width: 8),
                              Text('Leaving…'),
                            ],
                          )
                        : const Text('Leave'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    if (left != true || !mounted) return;
    final leftName = _profile.name;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Left "$leftName".')),
    );
    Navigator.of(context).pop();
  }

  Future<void> _addPlayer() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add player to ${_profile.name}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Player name'),
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                Navigator.pop(ctx, ctrl.text.trim());
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 500), ctrl.dispose);
    if (name == null || name.isEmpty) return;
    if (_profile.players.any((p) => p.toLowerCase() == name.toLowerCase())) {
      return;
    }
    if (!_isSaved) {
      await _persist(_profile);
    }
    await LocalEventStore.instance.addPlayerToClub(
      teamId: _profile.id,
      displayName: name,
    );
    await _loadClaimed();
  }

  int _designationOrder(String? d) => switch (d) {
        'C' => 0,
        'VC' => 1,
        'WK' => 2,
        _ => 3,
      };

  Future<String?> _renamePlayer(
    String oldName, {
    bool hasStats = false,
  }) async {
    final ctrl = TextEditingController(text: oldName);
    String? errorText;
    final renamed = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          void submit() {
            final clean = ctrl.text.trim();
            if (clean.isEmpty) {
              setDialogState(() => errorText = 'Enter a player name.');
              return;
            }
            if (clean.toLowerCase() == oldName.toLowerCase() &&
                clean == oldName) {
              Navigator.pop(ctx);
              return;
            }
            final duplicate = _profile.players.any(
              (p) =>
                  p.toLowerCase() == clean.toLowerCase() &&
                  p.toLowerCase() != oldName.toLowerCase(),
            );
            if (duplicate) {
              setDialogState(
                () => errorText = '"$clean" is already in this squad.',
              );
              return;
            }
            Navigator.pop(ctx, clean);
          }

          return AlertDialog(
            title: const Text('Rename player'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    hintText: 'Player name',
                    errorText: errorText,
                  ),
                  onChanged: (_) {
                    if (errorText != null) {
                      setDialogState(() => errorText = null);
                    }
                  },
                  onSubmitted: (_) => submit(),
                ),
                if (hasStats) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Updates across your squad, past scorecards, and career stats automatically.',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: submit,
                child: const Text('Save'),
              ),
            ],
          );
        },
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 500), ctrl.dispose);
    if (renamed == null || renamed.isEmpty || renamed == oldName) return null;

    final target = _profile.playerByName(oldName);
    if (target == null) return null;
    await LocalEventStore.instance.renamePlayer(target.id, renamed);
    await _loadClaimed();
    return renamed;
  }

  Future<void> _openPlayerProfileSheet(
    String playerName,
    PlayerCareerStats? stats,
  ) async {
    var currentName = playerName;
    final initialMeta = _profile.metaFor(currentName);
    final isClaimed = _claimedPlayers.contains(currentName.toLowerCase());
    final initialTarget = _profile.playerByName(currentName);
    final signedInUid = LocalEventStore.instance.signedInUserId;
    final isSelfClaimed = initialTarget != null &&
        signedInUid != null &&
        initialTarget.userId == signedInUid;
    final initialRole = initialMeta.role.trim();
    final initialDesignation =
        (initialMeta.designation != null &&
                initialMeta.designation!.trim().isNotEmpty)
            ? initialMeta.designation!.trim()
            : null;
    var role = initialRole;
    var designation = initialDesignation;
    var isSaving = false;
    String? saveError;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final c = ctx.crease;
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final normalizedDes =
                (designation != null && designation!.trim().isNotEmpty)
                    ? designation!.trim()
                    : null;
            final hasChanges =
                role != initialRole || normalizedDes != initialDesignation;

            return PopScope(
              canPop: !isSaving,
              child: GlassSurface(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(CreaseRadius.sheet),
              ),
              fillColor: c.surfaceSheet,
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: c.hairline,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        CreasePlayerAvatar(
                          name: currentName,
                          size: 48,
                          highlighted: true,
                          avatarUrl: _memberAvatars[currentName.toLowerCase()],
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      currentName,
                                      style: Theme.of(ctx).textTheme.titleLarge,
                                    ),
                                  ),
                                  if (isClaimed) ...[
                                    const SizedBox(width: 6),
                                    Icon(
                                      Icons.verified_rounded,
                                      size: 18,
                                      color: c.pitchGreen,
                                    ),
                                  ] else if (_canEdit) ...[
                                    const SizedBox(width: 2),
                                    IconButton(
                                      tooltip: 'Rename player',
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 32,
                                        minHeight: 32,
                                      ),
                                      icon: Icon(
                                        Icons.edit_outlined,
                                        size: 17,
                                        color: c.inkSecondary,
                                      ),
                                      onPressed: () async {
                                        final updated = await _renamePlayer(
                                          currentName,
                                          hasStats: stats != null,
                                        );
                                        if (updated != null && ctx.mounted) {
                                          setModalState(
                                            () => currentName = updated,
                                          );
                                        }
                                      },
                                    ),
                                  ],
                                ],
                              ),
                              Text(
                                '${_profile.name}${role.isNotEmpty ? ' · $role' : ''}',
                                style: Theme.of(ctx).textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        if (stats != null)
                          IconButton(
                            tooltip: 'Share player card',
                            icon: const Icon(Icons.share_rounded, size: 20),
                            onPressed: () {
                              PlayerCareerPoster.sharePlayerCard(
                                playerName: currentName,
                                stats: stats,
                                role: role,
                                teamName: _profile.name,
                              );
                            },
                          ),
                        IconButton(
                          tooltip: 'Full profile',
                          icon: const Icon(Icons.open_in_new_rounded, size: 19),
                          onPressed: () {
                            Navigator.pop(ctx);
                            final player = _profile.playerByName(currentName);
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => PlayerProfileScreen(
                                  playerName: currentName,
                                  playerId: player?.id,
                                  userId: player?.userId,
                                  role: role,
                                  teams: [_profile.name],
                                  isVerified: isClaimed,
                                  matches: widget.matches,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (stats != null) ...[
                      Row(
                        children: [
                          _MiniStatBox(
                            label: 'Matches',
                            value: '${stats.matchesPlayed}',
                          ),
                          const SizedBox(width: 8),
                          _MiniStatBox(label: 'Runs', value: '${stats.runs}'),
                          const SizedBox(width: 8),
                          _MiniStatBox(
                            label: 'Wickets',
                            value: '${stats.wickets}',
                          ),
                          const SizedBox(width: 8),
                          _MiniStatBox(
                            label: 'MVP',
                            value: '${stats.mvpPoints}',
                            highlight: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ] else ...[
                      Text(
                        'No match stats recorded yet for $currentName.',
                        style: Theme.of(ctx).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (_canEdit) ...[
                      Text(
                        'Team designation',
                        style: Theme.of(ctx).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final d in <String?>[
                            null,
                            ...SquadPlayerMeta.designations,
                          ])
                            ChoiceChip(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              labelPadding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              label: Text(
                                d == null
                                    ? 'None'
                                    : d == 'C'
                                        ? 'Captain'
                                        : d == 'VC'
                                            ? 'Vice-Capt'
                                            : 'Keeper',
                              ),
                              selected: designation == d,
                              selectedColor: c.pitchGreen,
                              labelStyle: TextStyle(
                                fontSize: 12.5,
                                color: designation == d
                                    ? Colors.white
                                    : c.inkPrimary,
                                fontWeight: designation == d
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                              side: BorderSide(
                                color: designation == d
                                    ? c.pitchGreen
                                    : c.hairline,
                              ),
                              onSelected: isSaving
                                  ? null
                                  : (_) => setModalState(() {
                                      designation = d;
                                      saveError = null;
                                    }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Playing role',
                        style: Theme.of(ctx).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final r in SquadPlayerMeta.roles)
                            ChoiceChip(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              labelPadding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              label: Text(r == 'Wicket-keeper' ? 'Keeper' : r),
                              selected: role == r,
                              selectedColor: c.pitchGreen,
                              labelStyle: TextStyle(
                                fontSize: 12.5,
                                color: role == r ? Colors.white : c.inkPrimary,
                                fontWeight: role == r
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                              side: BorderSide(
                                color: role == r ? c.pitchGreen : c.hairline,
                              ),
                              onSelected: isSaving
                                  ? null
                                  : (_) => setModalState(() {
                                      role = role == r ? '' : r;
                                      saveError = null;
                                    }),
                            ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      if (saveError != null) ...[
                        Text(
                          saveError!,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: c.wicketRed,
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      FilledButton(
                        style: FilledButton.styleFrom(
                          disabledBackgroundColor:
                              isSaving ? c.pitchGreen : null,
                          disabledForegroundColor:
                              isSaving ? c.onPitchGreen : null,
                        ),
                        onPressed: (!hasChanges || isSaving)
                            ? null
                            : () async {
                                setModalState(() {
                                  isSaving = true;
                                  saveError = null;
                                });
                                try {
                                  final target =
                                      _profile.playerByName(currentName);
                                  if (target != null) {
                                    await LocalEventStore.instance
                                        .updatePlayerRole(
                                      target.id,
                                      role: role,
                                      designation: normalizedDes,
                                    );
                                    await _loadClaimed();
                                  }
                                  if (ctx.mounted) Navigator.pop(ctx);
                                } catch (_) {
                                  if (ctx.mounted) {
                                    setModalState(() {
                                      isSaving = false;
                                      saveError =
                                          'Could not save player role. Please try again.';
                                    });
                                  }
                                }
                              },
                        child: isSaving
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: c.onPitchGreen,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Text('Saving…'),
                                ],
                              )
                            : const Text('Save player role'),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (isClaimed)
                            Expanded(
                              child: TextButton(
                                onPressed: isSaving
                                    ? null
                                    : () async {
                                        Navigator.pop(ctx);
                                        await _confirmUnlinkPlayer(currentName);
                                      },
                                child: const Text('Unlink account'),
                              ),
                            ),
                          Expanded(
                            child: TextButton(
                              style: TextButton.styleFrom(
                                foregroundColor: c.wicketRed,
                              ),
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                      final target =
                                          _profile.playerByName(currentName);
                                      if (target == null) return;
                                      setModalState(() {
                                        isSaving = true;
                                        saveError = null;
                                      });
                                      try {
                                        if (isClaimed) {
                                          await LocalEventStore.instance
                                              .unlinkTeamPlayer(target.id);
                                        }
                                        await LocalEventStore.instance
                                            .archivePlayer(target.id);
                                        await _loadClaimed();
                                        if (ctx.mounted) Navigator.pop(ctx);
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(context)
                                          ..hideCurrentSnackBar()
                                          ..showSnackBar(
                                            SnackBar(
                                              duration:
                                                  const Duration(seconds: 4),
                                              content: Text(
                                                'Removed $currentName from ${_profile.name}',
                                              ),
                                              action: SnackBarAction(
                                                label: 'Undo',
                                                onPressed: () async {
                                                  await LocalEventStore.instance
                                                      .savePlayer(
                                                    target.copyWith(
                                                      archived: false,
                                                    ),
                                                  );
                                                  await _loadClaimed();
                                                },
                                              ),
                                            ),
                                          );
                                      } catch (_) {
                                        if (ctx.mounted) {
                                          setModalState(() {
                                            isSaving = false;
                                            saveError =
                                                'Could not remove player. Check connection and try again.';
                                          });
                                        }
                                      }
                                    },
                              child: const Text('Remove player'),
                            ),
                          ),
                        ],
                      ),
                    ] else if (!widget.readOnlyPublic &&
                        _isSaved &&
                        isSelfClaimed) ...[
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: c.wicketRed,
                        ),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await _confirmUnlinkPlayer(currentName, isSelf: true);
                        },
                        child: const Text('Unlink my account'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
          },
        );
      },
    );
  }
}
