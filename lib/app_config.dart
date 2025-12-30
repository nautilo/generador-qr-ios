class AppConfig {
  /// Base URL de producción (HTTPS).
  /// Puedes sobreescribirla al compilar con:
  /// flutter run --dart-define=BASE_URL=https://tudominio.com
  static const String baseUrl = String.fromEnvironment(
    'BASE_URL',
    defaultValue: 'https://gladiatorcontrolbase.com',
  );

  /// Construye un Uri absoluto a partir de un path (con /) y query params opcionales.
  static Uri uri(String path, [Map<String, dynamic>? query]) {
    final base = Uri.parse(baseUrl);
    return base.replace(
      path: path.startsWith('/') ? path : '/$path',
      queryParameters: query?.map((k, v) => MapEntry(k, v.toString())),
    );
  }
}
