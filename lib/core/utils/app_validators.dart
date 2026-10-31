class AppValidators {
  static String? Function(String?) required(String message) {
    return (String? value) {
      if (value == null || value.trim().isEmpty) {
        return message;
      }
      return null;
    };
  }

  static String? price(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Indica el precio.';
    }
    if (double.tryParse(value) == null) {
      return 'Indica un número válido.';
    }
    if (double.parse(value) < 0) {
      return 'El precio no puede ser negativo.';
    }
    return null;
  }
}
