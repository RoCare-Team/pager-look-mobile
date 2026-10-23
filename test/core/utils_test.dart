import 'package:flutter_test/flutter_test.dart';
import 'package:veriwork_mobile/core/network/api_exception.dart';
import 'package:veriwork_mobile/core/network/upload.dart';
import 'package:veriwork_mobile/core/utils/formatters.dart';
import 'package:veriwork_mobile/core/utils/json.dart';
import 'package:veriwork_mobile/core/utils/validators.dart';
import 'package:veriwork_mobile/data/api/auth_api.dart';
import 'package:veriwork_mobile/data/api/enterprise_api.dart';

void main() {
  group('json helpers', () {
    test('listFrom accepts bare lists and wrapped lists', () {
      expect(listFrom([{'a': 1}]), [{'a': 1}]);
      expect(listFrom({'items': [{'a': 1}]}), [{'a': 1}]);
      expect(listFrom({'requests': [{'a': 1}]}, ['requests']), [{'a': 1}]);
      expect(listFrom(null), isEmpty);
    });

    test('pick reads dotted paths through maps and lists', () {
      final data = {'education': {'class10': {'board': 'CBSE'}}, 'jobs': [{'company': 'Acme'}]};
      expect(pick(data, 'education.class10.board'), 'CBSE');
      expect(pick(data, 'jobs.0.company'), 'Acme');
      expect(pick(data, 'jobs.4.company'), isNull);
    });

    test('idOf prefers _id then id', () {
      expect(idOf({'_id': 'x', 'id': 'y'}), 'x');
      expect(idOf({'id': 'y'}), 'y');
      expect(idOf(null), '');
    });

    test('scalar coercion', () {
      expect(asBool('true'), isTrue);
      expect(asBool(1), isTrue);
      expect(asBool(null), isFalse);
      expect(asInt('42'), 42);
      expect(str(null, '—'), '—');
      expect(strOrNull('  '), isNull);
    });
  });

  group('formatters', () {
    test('initials', () {
      expect(initials('Asha Kumari Rao'), 'AK');
      expect(initials(''), '??');
    });
    test('humanize', () {
      expect(humanize('awaiting_consent'), 'Awaiting consent');
      expect(humanize('inProgress'), 'In progress');
    });
    test('formatDate', () {
      expect(formatDate('2026-03-12T10:00:00Z'), contains('2026'));
      expect(formatDate(null), '—');
    });
    test('maskAadhaar keeps the last four digits', () {
      expect(maskAadhaar('2345 6789 0123'), 'XXXX XXXX 0123');
    });
  });

  group('validators', () {
    test('email', () {
      expect(emailValidator('hr@technova.com'), isNull);
      expect(emailValidator('nope'), isNotNull);
    });
    test('password matches the backend minimum', () {
      expect(passwordValidator('short'), isNotNull);
      expect(passwordValidator('longenough'), isNull);
    });
    test('aadhaar uses the Verhoeff checksum like the backend', () {
      expect(isValidAadhaarNumber('234123412346'), isTrue);
      expect(isValidAadhaarNumber('234123412347'), isFalse);
      expect(isValidAadhaarNumber('123412341234'), isFalse, reason: 'cannot start with 1');
      expect(aadhaarValidator('2341 2341 2346'), isNull);
    });
  });

  group('payload builders mirror the web', () {
    test('normalizePhone', () {
      expect(normalizePhone('+91', '98765 43210'), '+919876543210');
      expect(normalizePhone('', '9876543210'), '+919876543210');
    });

    test('normalizeRegisterPhone', () {
      expect(normalizeRegisterPhone('9876543210'), '+919876543210');
      expect(normalizeRegisterPhone('919876543210'), '+919876543210');
      expect(normalizeRegisterPhone('+44 7700 900123'), '+447700900123');
    });

    test('buildEnterpriseRegisterPayload trims, uppercases ids and drops blanks', () {
      final payload = buildEnterpriseRegisterPayload(
        email: ' hr@acme.com ',
        password: 'Secret123',
        confirmPassword: 'Secret123',
        companyLegalName: ' Acme Pvt Ltd ',
        industry: 'it',
        companySize: '11-50',
        workEmail: 'hr@acme.com',
        contactName: 'Asha',
        phone: '9876543210',
        country: 'India',
        pincode: '560 001',
        brn: 'u12345',
        state: ' ',
      );
      expect(payload['email'], 'hr@acme.com');
      expect(payload['companyLegalName'], 'Acme Pvt Ltd');
      expect(payload['phone'], '+919876543210');
      expect(payload['pincode'], '560001');
      expect(payload['brn'], 'U12345');
      expect(payload['city'], '');
      expect(payload.containsKey('state'), isFalse);
      expect(payload.containsKey('taxId'), isFalse);
      expect(payload.containsKey('companyType'), isFalse);
    });

    test('enterprise document keys map taxCertificate to tax', () {
      expect(enterpriseDocType('taxCertificate'), 'tax');
      expect(uploadedEnterpriseDocument({'tax': {'url': 'u'}}, 'taxCertificate'), {'url': 'u'});
    });
  });

  group('uploads', () {
    test('mimetype is resolved from the file name', () {
      const pdf = PickedDoc(path: '/tmp/a.pdf', name: 'offer.pdf', size: 1000);
      const jpg = PickedDoc(path: '/tmp/b', name: 'card.jpg', size: 1000);
      expect(pdf.resolvedMimeType, 'application/pdf');
      expect(jpg.resolvedMimeType, 'image/jpeg');
    });

    test('size and type limits match the web', () {
      expect(validateDocument(const PickedDoc(path: 'x', name: 'a.pdf', size: 11 * 1024 * 1024)), isNotNull);
      expect(validateDocument(const PickedDoc(path: 'x', name: 'a.docx', size: 100)), isNotNull);
      expect(validateDocument(const PickedDoc(path: 'x', name: 'a.png', size: 100)), isNull);
      expect(validateImage(const PickedDoc(path: 'x', name: 'a.pdf', size: 100)), isNotNull);
    });
  });

  test('ApiException.fromResponse falls back to the status', () {
    expect(ApiException.fromResponse(502, '<html>').message, 'Request failed (502)');
    expect(ApiException.fromResponse(429, {'message': 'Slow down', 'details': {'retryAfterSeconds': 30}}).retryAfterSeconds, 30);
  });
}
