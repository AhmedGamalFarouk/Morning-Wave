import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../widgets/paper_card.dart';
import '../widgets/sun_painter.dart';

/// The grown child's one setup question: what do you call your parent?
/// Morning Wave greets the parent with that name every morning.
class StartFamilyScreen extends StatefulWidget {
  const StartFamilyScreen({
    super.key,
    required this.onStart,
    this.childName,
    this.onBack,
    this.onHaveCode,
  });

  /// For a brother or sister joining a family that already exists.
  final VoidCallback? onHaveCode;

  /// Null once the family exists; otherwise a line to show.
  final Future<String?> Function(String parentName) onStart;
  final String? childName;

  /// Shown when adding a second parent, to go back home.
  final VoidCallback? onBack;

  @override
  State<StartFamilyScreen> createState() => _StartFamilyScreenState();
}

class _StartFamilyScreenState extends State<StartFamilyScreen> {
  static const _usual = ['Mom', 'Dad', 'Mum', 'Mama', 'Papa'];

  final _name = TextEditingController();
  var _busy = false;
  String? _hint;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final name = _name.text.trim();
    if (_busy || name.isEmpty) return;
    setState(() {
      _busy = true;
      _hint = null;
    });
    final hint = await widget.onStart(name);
    if (mounted) {
      setState(() {
        _busy = false;
        _hint = hint;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final hello = widget.childName == null ? 'Hi' : 'Hi ${widget.childName}';
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: widget.onBack == null
                  ? const SizedBox(height: 56)
                  : TextButton(
                      onPressed: widget.onBack,
                      child: const Text('Back'),
                    ),
            ),
            const Center(child: SunMark(size: 88)),
            const SizedBox(height: 16),
            Semantics(
              header: true,
              child: Text(
                '$hello! Who are the good mornings from?',
                textAlign: TextAlign.center,
                style: text.displayMedium,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Write it the way you’d say it. They’ll be greeted by this '
              'name every morning.',
              textAlign: TextAlign.center,
              style: text.bodyLarge?.copyWith(color: Palette.inkSoft),
            ),
            const SizedBox(height: 28),
            PaperCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final name in _usual)
                        ChoiceChip(
                          label: Text(name),
                          labelStyle: text.labelLarge,
                          selected: _name.text == name,
                          showCheckmark: false,
                          selectedColor: Palette.sun,
                          backgroundColor: Palette.card,
                          side: const BorderSide(color: Palette.peach),
                          shape: const StadiumBorder(),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          onSelected: _busy ? null : (_) => _name.text = name,
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: _name,
                    enabled: !_busy,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _start(),
                    style: text.headlineSmall,
                    decoration: const InputDecoration(
                      labelText: 'Or their name',
                    ),
                  ),
                  if (_hint != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _hint!,
                      style: text.bodyMedium?.copyWith(color: Palette.inkSoft),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy || _name.text.trim().isEmpty
                        ? null
                        : _start,
                    child: Text(_busy ? 'One moment…' : 'Start our mornings'),
                  ),
                  if (widget.onHaveCode != null) ...[
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _busy ? null : widget.onHaveCode,
                      child: const Text('I have a code from my family'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
