import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/features/capture/data/sms_outbox.dart';

void main() {
  group('SmsOutbox.clientIdFor', () {
    test('is deterministic for the same sms', () {
      final a = SmsOutbox.clientIdFor('AirtelMoney', 1700000000000, 'You received MK5000');
      final b = SmsOutbox.clientIdFor('AirtelMoney', 1700000000000, 'You received MK5000');
      expect(a, b);
    });

    test('ignores surrounding whitespace in the body', () {
      final a = SmsOutbox.clientIdFor('NBM', 1, 'Credited MWK 100');
      final b = SmsOutbox.clientIdFor('NBM', 1, '  Credited MWK 100\n');
      expect(a, b);
    });

    test('differs when time, sender or content differ', () {
      final base = SmsOutbox.clientIdFor('NBM', 1, 'Credited MWK 100');
      expect(SmsOutbox.clientIdFor('NBM', 2, 'Credited MWK 100'), isNot(base));
      expect(SmsOutbox.clientIdFor('FDH', 1, 'Credited MWK 100'), isNot(base));
      expect(SmsOutbox.clientIdFor('NBM', 1, 'Credited MWK 101'), isNot(base));
    });

    test('fits the server 64 character limit', () {
      final id = SmsOutbox.clientIdFor('NBM', 9999999999999, 'x' * 1000);
      expect(id.length, lessThanOrEqualTo(64));
    });
  });
}
