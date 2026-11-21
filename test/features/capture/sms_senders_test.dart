import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/features/capture/data/sms_senders.dart';

void main() {
  test('bank short codes belong to their bank', () {
    expect(SmsSenders.providerFor('52525'), 'fdh');
    expect(SmsSenders.providerFor('626626'), 'nbm');
    expect(SmsSenders.providerFor('CenteBank'), 'centenary');
  });

  test('named senders match whatever their capitals or spacing', () {
    expect(SmsSenders.providerFor('AirtelMoney'), 'airtel');
    expect(SmsSenders.providerFor('TNM Mpamba'), 'mpamba');
    expect(SmsSenders.providerFor('FDH BANK'), 'fdh');
  });

  test('NBS is not National Bank', () {
    expect(SmsSenders.providerFor('NBS Bank'), 'nbs');
    expect(SmsSenders.matches('NBS Bank', 'nbm'), isFalse);
  });

  test('an unknown sender can be filtered on exactly', () {
    expect(SmsSenders.providerFor('MySacco'), isNull);
    expect(SmsSenders.matches('MySacco', '${SmsSenders.senderPrefix}MySacco'), isTrue);
    expect(SmsSenders.matches('OtherSacco', '${SmsSenders.senderPrefix}MySacco'), isFalse);
  });
}
