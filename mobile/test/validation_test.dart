import 'package:flutter_test/flutter_test.dart';
import 'package:ecoloop/services/data_repository.dart';

void main() {
  group('Validation', () {
    test('name required', () {
      expect(Validation.validateName(''), isNotNull);
      expect(Validation.validateName('   '), isNotNull);
      expect(Validation.validateName('Sara'), isNull);
    });

    test('email must look like an email', () {
      expect(Validation.validateEmail('not-an-email'), isNotNull);
      expect(Validation.validateEmail('a@b'), isNotNull);
      expect(Validation.validateEmail('user@example.com'), isNull);
    });

    test('password minimum length', () {
      expect(Validation.validatePassword('12345'), isNotNull);
      expect(Validation.validatePassword('123456'), isNull);
    });
  });
}