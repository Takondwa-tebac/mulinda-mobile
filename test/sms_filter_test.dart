import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/features/capture/data/sms_auto_capture.dart';

void main() {
  group('which SMS look like money on the phone', () {
    test('real money messages with an amount are kept', () {
      for (final body in [
        'Payment of MK200 Till number PAYCHANGU Airtel money bal is MK26172.0.',
        'You have received MWK 5,000 from JOHN BANDA. Balance MWK 12,300.',
        'Dear Customer, your account has been credited with MWK 4000 on 06-JUN-2026.',
        'Txn Alert: Amount: 5,000.00 MWK debited at SHOPRITE',
        'Paid K 1,500 to Shoprite. Ref TX99.',
        'Transfer of 20,000 MWK was successful.',
      ]) {
        expect(SmsAutoCapture.isFinancialSms(body), true, reason: body);
      }
    });

    test('notices with money words but no amount stay on the phone', () {
      for (final body in [
        'Dial *211# to check your Airtel Money balance.',
        'Your TNM request has been received. We will get back to you.',
        'Dear customer, thank you for banking with National Bank.',
        'FDH has received your application.',
        'Your transaction could not be completed. Please try again.',
      ]) {
        expect(SmsAutoCapture.isFinancialSms(body), false, reason: body);
      }
    });

    test('personal messages stay on the phone', () {
      expect(SmsAutoCapture.isFinancialSms('See you at 5 tomorrow, ok?'), false);
      expect(SmsAutoCapture.isFinancialSms('Happy birthday! K5 words say it all'), false);
    });
  });
}
