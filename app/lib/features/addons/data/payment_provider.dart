import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:prostuti/features/addons/data/addon_models.dart';

/// Outcome of a purchase attempt.
@immutable
sealed class PaymentResult {
  const PaymentResult();

  /// Paid and verified by the server; the entitlement already exists.
  const factory PaymentResult.success({required String addonCode, DateTime? expiresAt, String? reference}) =
      PaymentSuccess;

  /// Paid, waiting for the gateway's confirmation (webhook) — poll later.
  const factory PaymentResult.pending({String? reference}) = PaymentPending;

  /// The user closed the payment page.
  const factory PaymentResult.cancelled() = PaymentCancelled;

  /// The gateway or the server rejected the payment.
  const factory PaymentResult.failed(Object error) = PaymentFailed;

  /// No payment method is available in this build yet.
  static const unavailable = PaymentUnavailable();
}

final class PaymentSuccess extends PaymentResult {
  const PaymentSuccess({required this.addonCode, this.expiresAt, this.reference});
  final String addonCode;
  final DateTime? expiresAt;
  final String? reference;
}

final class PaymentPending extends PaymentResult {
  const PaymentPending({this.reference});
  final String? reference;
}

final class PaymentCancelled extends PaymentResult {
  const PaymentCancelled();
}

final class PaymentFailed extends PaymentResult {
  const PaymentFailed(this.error);
  final Object error;
}

final class PaymentUnavailable extends PaymentResult {
  const PaymentUnavailable();
}

/// Pluggable payment gateway.
///
/// A real implementation (bKash, Nagad, SSLCommerz, Google Play Billing…)
/// should never grant access on the client. The expected flow is:
///  1. call an Edge Function that inserts a `payments` row (`initiated`) and
///     returns the gateway checkout URL / product id;
///  2. open the gateway (web view, app switch or Play Billing sheet);
///  3. the gateway's webhook (or a receipt-verification function) marks the
///     payment `success` and inserts the `user_entitlements` row with the
///     service role;
///  4. return [PaymentResult.success] (or `pending` while the webhook is in
///     flight) — the UI then calls `refreshFeatureAccess`.
abstract class PaymentProvider {
  const PaymentProvider();

  /// Stable id stored in `payments.provider` (e.g. `bkash`).
  String get id;

  /// Whether purchases can be made right now.
  bool get isAvailable;

  Future<PaymentResult> purchase(Addon addon);
}

/// Default provider until a gateway is integrated: purchases are not possible
/// yet, so the store points people to free trials and promo codes.
class ManualPaymentProvider extends PaymentProvider {
  const ManualPaymentProvider();

  @override
  String get id => 'manual';

  @override
  bool get isAvailable => false;

  @override
  Future<PaymentResult> purchase(Addon addon) async => PaymentResult.unavailable;
}

/// Swap with `overrideWithValue` (or change here) once a gateway ships.
final paymentProviderProvider = Provider<PaymentProvider>((ref) => const ManualPaymentProvider());
