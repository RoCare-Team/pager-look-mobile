import 'package:flutter_test/flutter_test.dart';
import 'package:veriwork_mobile/features/public/scan_routing.dart';

void main() {
  group('routeForScannedValue', () {
    test('maps PagerLook web links onto app routes', () {
      expect(routeForScannedValue('https://www.pagerlook.com/join/AB12CD'), '/join/AB12CD');
      expect(routeForScannedValue('https://www.pagerlook.com/u/priya-s'), '/u/priya-s');
      expect(routeForScannedValue('https://www.pagerlook.com/verify-employment/tok123'), '/verify-employment/tok123');
      expect(routeForScannedValue('https://www.pagerlook.com/employee/join?token=abc'), '/employee/join?token=abc');
      expect(
        routeForScannedValue('https://www.pagerlook.com/enterprise/accept-invite?token=xyz'),
        '/enterprise/accept-invite?token=xyz',
      );
    });

    test('accepts bare paths and scheme-less hosts', () {
      expect(routeForScannedValue('/u/priya'), '/u/priya');
      expect(routeForScannedValue('www.pagerlook.com/join/AB12CD'), '/join/AB12CD');
    });

    test('rejects unrelated or incomplete values', () {
      expect(routeForScannedValue(''), isNull);
      expect(routeForScannedValue('https://example.com/'), isNull);
      expect(routeForScannedValue('mailto:hr@acme.com'), isNull);
      expect(routeForScannedValue('https://www.pagerlook.com/employee/join'), isNull);
      expect(routeForScannedValue('https://www.pagerlook.com/admin/dashboard'), isNull);
    });
  });

  group('routeForJoinCode', () {
    test('accepts a bare code or a link', () {
      expect(routeForJoinCode('AB12CD'), '/join/AB12CD');
      expect(routeForJoinCode('https://www.pagerlook.com/join/AB12CD'), '/join/AB12CD');
      expect(routeForJoinCode('no spaces allowed'), isNull);
    });
  });
}
