part of '../teams_tab_view.dart';

Future<TeamProfile?> showCreateTeamSheet(
  BuildContext context, {
  List<String> existingTeamNames = const [],
}) {
  return showModalBottomSheet<TeamProfile>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _CreateTeamSheet(existingTeamNames: existingTeamNames),
  );
}

class _CreateTeamSheet extends StatefulWidget {
  const _CreateTeamSheet({this.existingTeamNames = const []});

  final List<String> existingTeamNames;

  @override
  State<_CreateTeamSheet> createState() => _CreateTeamSheetState();
}

class _CreateTeamSheetState extends State<_CreateTeamSheet> {
  static const _uuid = Uuid();
  final _nameCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  bool _isMyTeam = true;
  String? _nameError;
  late Map<String, String> _existingByLower;

  @override
  void initState() {
    super.initState();
    _existingByLower = {
      for (final n in widget.existingTeamNames) n.trim().toLowerCase(): n,
    };
    if (_existingByLower.isEmpty) {
      _loadExistingNames();
    }
  }

  Future<void> _loadExistingNames() async {
    final teams = await LocalEventStore.instance.listTeams();
    if (!mounted) return;
    setState(() {
      _existingByLower = {
        for (final t in teams) t.name.trim().toLowerCase(): t.name,
      };
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Enter a team name.');
      return;
    }
    final existing = _existingByLower[name.toLowerCase()];
    if (existing != null) {
      setState(
        () => _nameError =
            'You already have "$existing" — open it from Teams to edit or pin it.',
      );
      return;
    }
    final loc = _locationCtrl.text.trim();
    Navigator.pop(
      context,
      TeamProfile(
        id: _uuid.v4(),
        name: name,
        location: loc.isEmpty ? null : loc,
        isMyTeam: _isMyTeam,
        squad: const [],
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.crease;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: GlassSurface(
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(CreaseRadius.sheet)),
        fillColor: c.surfaceSheet,
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const CreaseSheetHeader(
              title: 'New team',
              subtitle: 'You can add players or share an invite code next.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                labelText: 'Team name',
                hintText: 'e.g. Model Town CC',
                errorText: _nameError,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _locationCtrl,
              textCapitalization: TextCapitalization.words,
              onSubmitted: (_) => _save(),
              decoration: const InputDecoration(
                labelText: 'City or area (optional)',
                hintText: 'e.g. Lahore, Model Town',
                prefixIcon: Icon(Icons.location_on_outlined, size: 19),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('My team'),
              subtitle: const Text('Pin to the top of your teams list'),
              activeThumbColor: c.pitchGreen,
              value: _isMyTeam,
              onChanged: (v) => setState(() => _isMyTeam = v),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _save,
              child: const Text('Create team'),
            ),
          ],
        ),
      ),
    );
  }
}

