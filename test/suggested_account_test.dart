import 'package:flutter_test/flutter_test.dart';
import 'package:mulinda_mobile/features/capture/screens/inbox_screen.dart';

void main() {
  test('suggests the account a message came from by its sender', () {
    expect(suggestedAccountFor('AirtelMoney')?.name, 'Airtel Money');
    expect(suggestedAccountFor('MPAMBA')?.name, 'TNM Mpamba');
    expect(suggestedAccountFor('NBM')?.type, 'bank');
    expect(suggestedAccountFor('CenteBank')?.name, 'Centenary Bank');
    expect(suggestedAccountFor('RandomBank'), isNull);
    expect(suggestedAccountFor(null), isNull);
  });
}
