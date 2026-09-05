class JsonInit {
  static String stringInit(String? value) => value ?? '';

  static List<T> listInit<T>(List<T>? value) => value ?? <T>[];
}
