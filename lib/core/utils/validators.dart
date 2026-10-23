/// Form validators. Return null when valid, an error message otherwise, so
/// they plug straight into `TextFormField.validator`.
library;

final RegExp _emailRe = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

bool isValidEmail(String? value) => value != null && _emailRe.hasMatch(value.trim());

String? requiredField(String? value, [String label = 'This field']) =>
    (value == null || value.trim().isEmpty) ? '$label is required' : null;

String? emailValidator(String? value, {bool required = true}) {
  if (value == null || value.trim().isEmpty) return required ? 'Email is required' : null;
  return isValidEmail(value) ? null : 'Enter a valid email address';
}

/// Indian mobile: 10 digits (optionally prefixed with +91 / 91).
String? phoneValidator(String? value, {bool required = true}) {
  final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return required ? 'Phone number is required' : null;
  if (digits.length < 10 || digits.length > 13) return 'Enter a valid phone number';
  return null;
}

/// Backend rule (`authValidators.js`): at least 8 characters.
String? passwordValidator(String? value) {
  if (value == null || value.isEmpty) return 'Password is required';
  if (value.length < 8) return 'Password must be at least 8 characters';
  return null;
}

String? pincodeValidator(String? value, {bool required = false}) {
  final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return required ? 'Pincode is required' : null;
  return digits.length == 6 ? null : 'Pincode must be 6 digits';
}

const List<List<int>> _verhoeffD = [
  [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
  [1, 2, 3, 4, 0, 6, 7, 8, 9, 5],
  [2, 3, 4, 0, 1, 7, 8, 9, 5, 6],
  [3, 4, 0, 1, 2, 8, 9, 5, 6, 7],
  [4, 0, 1, 2, 3, 9, 5, 6, 7, 8],
  [5, 9, 8, 7, 6, 0, 4, 3, 2, 1],
  [6, 5, 9, 8, 7, 1, 0, 4, 3, 2],
  [7, 6, 5, 9, 8, 2, 1, 0, 4, 3],
  [8, 7, 6, 5, 9, 3, 2, 1, 0, 4],
  [9, 8, 7, 6, 5, 4, 3, 2, 1, 0],
];

const List<List<int>> _verhoeffP = [
  [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
  [1, 5, 7, 6, 2, 8, 3, 0, 9, 4],
  [5, 8, 0, 3, 7, 9, 6, 1, 4, 2],
  [8, 9, 1, 6, 0, 4, 3, 5, 2, 7],
  [9, 4, 5, 3, 1, 2, 6, 8, 7, 0],
  [4, 2, 8, 6, 5, 7, 3, 9, 0, 1],
  [2, 7, 9, 3, 8, 0, 6, 4, 1, 5],
  [7, 0, 4, 6, 9, 1, 3, 2, 5, 8],
];

/// Verhoeff checksum — the backend (`utils/aadhaar.js`) rejects numbers that fail it.
bool isValidAadhaarNumber(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (!RegExp(r'^[2-9]\d{11}$').hasMatch(digits)) return false;
  var c = 0;
  final reversed = digits.split('').reversed.map(int.parse).toList();
  for (var i = 0; i < reversed.length; i++) {
    c = _verhoeffD[c][_verhoeffP[i % 8][reversed[i]]];
  }
  return c == 0;
}

String? aadhaarValidator(String? value) {
  final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.length != 12) return 'Aadhaar number must be 12 digits';
  if (!isValidAadhaarNumber(digits)) return 'Enter a valid Aadhaar number';
  return null;
}
