import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// The family plan: $59.99/yr, paid by the adult child. The parent's daily
/// check-in and missed-morning alerts are never gated on this — only paid
/// extras (photos, voice notes) check [isEntitled].
const familyPlanEntitlement = 'family_plan';

/// What the paywall shows for the family plan package, when known.
typedef PlanOffer = ({String priceString, String? introPriceString});

abstract interface class SubscriptionService {
  /// True once the signed-in family holds the family plan entitlement.
  /// Starts false and updates as purchases complete.
  ValueListenable<bool> get isEntitled;

  /// The family plan's price, once RevenueCat has it. Null until loaded.
  Future<PlanOffer?> loadOffer();

  /// Starts checkout for the family plan through Google Play Billing.
  /// Throws on failure; a user cancelling isn't a failure and just leaves
  /// [isEntitled] unchanged.
  Future<void> purchase();

  /// Restores a purchase made on another device or after a reinstall.
  Future<void> restore();
}

/// Wraps RevenueCat's SDK. Identifies the family by RevenueCat's own
/// anonymous id; "Restore a purchase" re-links a reinstall or a second
/// phone signed into the same Google Play account.
class RevenueCatSubscriptionService implements SubscriptionService {
  RevenueCatSubscriptionService({required String apiKey}) : _apiKey = apiKey {
    _init();
  }

  final String _apiKey;
  final _entitled = ValueNotifier<bool>(false);

  /// Cached by [loadOffer] and reused by [purchase], so tapping "Start the
  /// family plan" doesn't re-fetch offerings the paywall already loaded.
  Package? _package;

  @override
  ValueListenable<bool> get isEntitled => _entitled;

  Future<void> _init() async {
    try {
      await Purchases.configure(PurchasesConfiguration(_apiKey));
      Purchases.addCustomerInfoUpdateListener(_onCustomerInfo);
      _onCustomerInfo(await Purchases.getCustomerInfo());
    } catch (error) {
      debugPrint('RevenueCat setup: $error');
    }
  }

  void _onCustomerInfo(CustomerInfo info) {
    _entitled.value = info.entitlements.active.containsKey(
      familyPlanEntitlement,
    );
  }

  @override
  Future<PlanOffer?> loadOffer() async {
    try {
      final offerings = await Purchases.getOfferings();
      _package = offerings.current?.availablePackages.firstOrNull;
      final product = _package?.storeProduct;
      if (product == null) return null;
      return (
        priceString: product.priceString,
        introPriceString: product.introductoryPrice?.priceString,
      );
    } catch (error) {
      debugPrint('Loading the family plan price: $error');
      return null;
    }
  }

  @override
  Future<void> purchase() async {
    final package =
        _package ??
        (await Purchases.getOfferings()).current?.availablePackages.firstOrNull;
    if (package == null) {
      throw StateError('The family plan isn’t set up yet.');
    }
    try {
      final result = await Purchases.purchase(PurchaseParams.package(package));
      _onCustomerInfo(result.customerInfo);
    } on PlatformException catch (error) {
      final userCancelled =
          PurchasesErrorHelper.getErrorCode(error) ==
          PurchasesErrorCode.purchaseCancelledError;
      if (!userCancelled) rethrow;
    }
  }

  @override
  Future<void> restore() async {
    final info = await Purchases.restorePurchases();
    _onCustomerInfo(info);
  }
}

/// Before Ahmed sets up a RevenueCat project and API key, the paywall shows
/// but nothing can actually be bought. Mirrors how Supabase and Firebase
/// degrade when unconfigured.
class NoopSubscriptionService implements SubscriptionService {
  const NoopSubscriptionService();

  @override
  ValueListenable<bool> get isEntitled => const _AlwaysFalse();

  @override
  Future<PlanOffer?> loadOffer() async => null;

  @override
  Future<void> purchase() async {
    throw StateError('The family plan isn’t set up yet.');
  }

  @override
  Future<void> restore() async {}
}

class _AlwaysFalse implements ValueListenable<bool> {
  const _AlwaysFalse();
  @override
  bool get value => false;
  @override
  void addListener(VoidCallback listener) {}
  @override
  void removeListener(VoidCallback listener) {}
}
