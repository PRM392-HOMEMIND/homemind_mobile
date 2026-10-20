import '../../core/config/env_config.dart';

// Consumption-only projection at every state/UI boundary. Provider fields are
// excluded by default, even when an old backend/cache returns a full order.
Map<String, Object?> consumptionPayment(Map payment) {
  Map<String, Object?> pick(Map value, List<String> fields) => {
    for (final key in fields)
      if (value.containsKey(key)) key: value[key],
  };
  return {
    ...pick(payment, [
      'id',
      'status',
      'financialState',
      'fulfillment',
      'amountPaid',
      'createdAt',
      'paidAt',
      'cancelledAt',
      'cancellationTimeSource',
    ]),
    'price': pick(
      payment['price'] as Map? ?? {},
      payment['financialState'] == 'PAID'
          ? ['plan', 'amount', 'currency']
          : ['plan'],
    ),
    'grant': pick(payment['grant'] as Map? ?? {}, [
      'plan',
      'startsAt',
      'expiresAt',
      'originalExpiresAt',
      'supersededAt',
    ]),
  };
}

Map<String, Object?> billingPaymentForDistribution(
  Map<String, Object?> payment,
) => EnvConfig.externalBillingAllowed ? payment : consumptionPayment(payment);

Map<String, Object?> billingOverviewForDistribution(
  Map<String, Object?> overview,
) => EnvConfig.externalBillingAllowed
    ? overview
    : {
        for (final key in [
          'entitlement',
          'subscription',
          'scheduled',
          'workspaceType',
          'eligibility',
          'nextOffset',
        ])
          if (overview.containsKey(key)) key: overview[key],
        'checkoutEnabled': false,
        'payments': [
          for (final payment in overview['payments'] as List? ?? [])
            consumptionPayment(payment as Map),
        ],
      };
