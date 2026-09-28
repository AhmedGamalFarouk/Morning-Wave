import 'package:flutter/material.dart';

import '../services/subscription.dart';
import '../theme/palette.dart';
import '../widgets/paper_card.dart';
import '../widgets/sun_painter.dart';
import '../widgets/whole_words_text.dart';

/// The family plan, shown to the child. $59.99/yr, one payment for the
/// whole family; the parent never sees this screen or pays anything.
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key, required this.subscription, this.parentName});

  final SubscriptionService subscription;

  /// Who the child is caring for, for a line of reassurance ("Mom never
  /// pays a thing").
  final String? parentName;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  PlanOffer? _offer;
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.subscription.loadOffer().then((offer) {
      if (mounted) setState(() => _offer = offer);
    });
  }

  Future<void> _run(
    Future<void> Function() action, {
    String Function()? whenDone,
  }) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      if (mounted && whenDone != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(whenDone())));
      }
    } catch (error) {
      debugPrint('Family plan: $error');
      if (mounted) {
        setState(() => _error = 'That didn’t go through. Give it another try?');
      }
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _restoreMessage() => widget.subscription.isEntitled.value
      ? 'Found it — the family plan is active.'
      : 'No past purchase found on this account.';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final parent = widget.parentName;
    return Scaffold(
      body: SafeArea(
        child: ValueListenableBuilder<bool>(
          valueListenable: widget.subscription.isEntitled,
          builder: (context, entitled, _) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('Back'),
                  ),
                ),
                const SizedBox(height: 8),
                PaperCard(
                  padding: const EdgeInsets.all(28),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Palette.glow, Palette.card],
                    stops: [0, 0.7],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SunMark(size: 88, warmth: 0.8),
                      const SizedBox(height: 16),
                      Semantics(
                        header: true,
                        child: WholeWordsText(
                          entitled
                              ? 'You’re all set'
                              : 'Keep the good mornings coming',
                          style: text.displayMedium,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        entitled
                            ? 'The family plan is active. Voice notes and '
                                  'photos are ready whenever your family '
                                  'wants them.'
                            : 'The family plan brings voice notes and photos '
                                  'to your family’s mornings, on top of the '
                                  'daily good mornings and alerts you '
                                  'already have.'
                                  '${parent == null ? '' : ' $parent never pays a thing — this is just for you.'}',
                        style: text.bodyLarge?.copyWith(color: Palette.inkSoft),
                      ),
                    ],
                  ),
                ),
                if (!entitled) ...[
                  const SizedBox(height: 20),
                  _PriceCard(offer: _offer),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _run(widget.subscription.purchase),
                    child: Text(
                      _offer?.introPriceString == null
                          ? 'Start the family plan'
                          : 'Start free, then ${_offer!.priceString}/yr',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: _busy
                          ? null
                          : () => _run(
                              widget.subscription.restore,
                              whenDone: _restoreMessage,
                            ),
                      child: const Text('Restore a purchase'),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      _error!,
                      style: text.bodyMedium?.copyWith(color: Palette.inkSoft),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Billed yearly through Google Play. Cancel any time in '
                    'Play Store subscriptions.',
                    textAlign: TextAlign.center,
                    style: text.bodyMedium?.copyWith(color: Palette.inkSoft),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _PriceCard extends StatelessWidget {
  const _PriceCard({required this.offer});

  final PlanOffer? offer;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final price = offer?.priceString ?? r'$59.99/yr';
    final intro = offer?.introPriceString;
    return PaperCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            intro == null ? price : '$intro, then $price',
            style: text.headlineSmall,
          ),
          const SizedBox(height: 4),
          Text(
            'For the whole family, every year.',
            style: text.bodyMedium?.copyWith(color: Palette.inkSoft),
          ),
        ],
      ),
    );
  }
}
