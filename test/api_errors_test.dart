import 'package:flutter_test/flutter_test.dart';
import 'package:hola_professional/core/network/api.dart';

/// HOLA 0.26.0 security errors, as people see them.
void main() {
  test("a refused password shows HOLA's message under the password field", () {
    const common = 'This password is too common. Choose one that is harder to guess.';
    final reg = apiToDomain(const ApiError(422, 'VALIDATION_FAILED', 'The request did not pass validation.', {'password': common}));
    expect(reg.field, 'password');
    expect(reg.message, common);
    // Change password sends it as newPassword.
    final change = apiToDomain(const ApiError(422, 'VALIDATION_FAILED', '', {'newPassword': common}), fieldNames: const {'newPassword': 'password'});
    expect(change.field, 'password');
    expect(change.message, common);
  });

  test('booking and upload limits show what HOLA says', () {
    const detail = 'You already have 5 upcoming bookings.';
    expect(apiToDomain(const ApiError(429, 'RATE_LIMITED', detail)).message, detail);
    expect(apiToDomain(const ApiError(429, 'RATE_LIMITED', '')).message, contains('Too many tries'));
    expect(apiToDomain(const ApiError(409, 'CONFLICT', 'You already have a booking at that time.')).message, 'You already have a booking at that time.');
  });

  test('a locked sign-in says so, under the password', () {
    final e = apiToDomain(const ApiError(429, 'ACCOUNT_LOCKED', 'Too many failed login attempts.'));
    expect(e.message, 'Too many failed login attempts. Please try again after 15 minutes.');
    expect(e.field, 'password');
  });
}
