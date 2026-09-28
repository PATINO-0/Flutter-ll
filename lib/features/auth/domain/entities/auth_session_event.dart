class AuthSessionEvent {
  const AuthSessionEvent({required this.isAuthenticated, this.userId});

  final bool isAuthenticated;
  final String? userId;
}
