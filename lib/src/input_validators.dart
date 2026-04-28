class InputValidators {
  static final RegExp _emailRegex = RegExp(
    r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$',
  );
  static final RegExp _passwordUppercaseRegex = RegExp(r'[A-Z]');
  static final RegExp _passwordSpecialCharRegex = RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-\[\]\\/`~;=+]' );
  static final RegExp _digitRegex = RegExp(r'\D');

  static String normalizePhone(String value) {
    final digits = value.replaceAll(_digitRegex, '');
    if (digits.length == 12 && digits.startsWith('91')) {
      return digits.substring(2);
    }
    return digits;
  }

  static bool isValidEmail(String value) {
    return _emailRegex.hasMatch(value.trim().toLowerCase());
  }

  static String? requiredText(String? value, {required String fieldName}) {
    if (value == null || value.trim().isEmpty) return '$fieldName is required';
    return null;
  }

  static String? email(String? value, {bool required = true}) {
    final input = value?.trim() ?? '';
    if (input.isEmpty) {
      return required ? 'Email is required' : null;
    }
    if (!isValidEmail(input)) return 'Enter a valid email address';
    return null;
  }

  static String? password(String? value, {int minLength = 6}) {
    final input = value ?? '';
    if (input.isEmpty) return 'Password is required';
    if (input.length < minLength) {
      return 'Password must be at least $minLength characters';
    }
    if (!_passwordUppercaseRegex.hasMatch(input)) {
      return 'Password must include at least one capital letter';
    }
    if (!_passwordSpecialCharRegex.hasMatch(input)) {
      return 'Password must include at least one special character';
    }
    return null;
  }

  static String? phone(
    String? value, {
    bool required = true,
    String fieldLabel = 'Mobile number',
  }) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) {
      return required ? '$fieldLabel is required' : null;
    }

    final digits = normalizePhone(raw);
    if (digits.length != 10) {
      return 'Enter a valid 10-digit $fieldLabel';
    }
    return null;
  }
}
