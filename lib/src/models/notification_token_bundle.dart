class NotificationTokenBundle {
  const NotificationTokenBundle({
    this.fcmToken,
    this.apnsToken,
    this.providerToken,
    this.oneSignalId,
    this.currentUserId,
  });

  final String? fcmToken;
  final String? apnsToken;
  final String? providerToken;
  final String? oneSignalId;
  final String? currentUserId;

  bool get hasTokens =>
      (fcmToken != null && fcmToken!.isNotEmpty) ||
      (apnsToken != null && apnsToken!.isNotEmpty) ||
      (oneSignalId != null && oneSignalId!.isNotEmpty);
}
