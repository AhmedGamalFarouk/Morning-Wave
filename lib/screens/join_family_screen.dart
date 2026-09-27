import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../widgets/paper_card.dart';
import '../widgets/sun_painter.dart';

/// The parent's only setup step: type the code their family gave them.
/// No account, no password. The words never blame a wrong code.
class JoinFamilyScreen extends StatefulWidget {
  const JoinFamilyScreen({super.key, required this.onJoin, this.onBack});

  /// Null once the parent is in; otherwise a gentle line to show under the
  /// field, such as when no family has that code.
  final Future<String?> Function(String code) onJoin;
  final VoidCallback? onBack;

  @override
  State<JoinFamilyScreen> createState() => _JoinFamilyScreenState();
}

class _JoinFamilyScreenState extends State<JoinFamilyScreen> {
  final _code = TextEditingController();
  var _busy = false;
  String? _hint;

  @override
  void initState() {
    super.initState();
    _code.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (_busy || _code.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _hint = null;
    });
    final hint = await widget.onJoin(_code.text);
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
            const SizedBox(height: 8),
            const Center(child: SunMark(size: 88)),
            const SizedBox(height: 16),
            Semantics(
              header: true,
              child: Text(
                'Hello! Let’s find your family',
                textAlign: TextAlign.center,
                style: text.displayMedium,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Your family has a short code for you. Type it here.',
              textAlign: TextAlign.center,
              style: text.bodyLarge?.copyWith(color: Palette.inkSoft),
            ),
            const SizedBox(height: 28),
            PaperCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Already 36sp; bigger scales push the code out of view.
                  MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.4,
                    child: TextField(
                      controller: _code,
                      autofocus: true,
                      enabled: !_busy,
                      textAlign: TextAlign.center,
                      textCapitalization: TextCapitalization.characters,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.go,
                      onSubmitted: (_) => _join(),
                      style: text.displayMedium?.copyWith(letterSpacing: 4),
                      decoration: InputDecoration(
                        labelText: 'Family code',
                        labelStyle: text.bodyMedium,
                        floatingLabelAlignment: FloatingLabelAlignment.center,
                        filled: true,
                        fillColor: Palette.paper,
                        border: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(16)),
                          borderSide: BorderSide(color: Palette.peach),
                        ),
                        enabledBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(16)),
                          borderSide: BorderSide(color: Palette.peach),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderRadius: BorderRadius.all(Radius.circular(16)),
                          borderSide: BorderSide(
                            color: Palette.sunEdge,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (_hint != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _hint!,
                      textAlign: TextAlign.center,
                      style: text.bodyMedium?.copyWith(color: Palette.inkSoft),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _busy || _code.text.trim().isEmpty
                        ? null
                        : _join,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(64, 72),
                      textStyle: text.headlineMedium,
                    ),
                    child: Text(_busy ? 'One moment…' : 'Join my family'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
