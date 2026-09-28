class AppException implements Exception {
  const AppException(this.userMessage);

  final String userMessage;

  @override
  String toString() => userMessage;
}
