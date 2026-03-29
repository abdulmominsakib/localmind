import 'package:flutter_riverpod/flutter_riverpod.dart';

class SubscriptionNotifier extends Notifier<bool> {
  @override
  bool build() {
    // Mocked state: false = Basic user, true = Premium user
    return false;
  }

  void togglePremium() {
    state = !state;
  }
}

final isPremiumUserProvider = NotifierProvider<SubscriptionNotifier, bool>(() {
  return SubscriptionNotifier();
});
