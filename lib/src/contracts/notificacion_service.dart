abstract class NotificacionService {
  Future<void> subscripcionUsuario({
    String? subscripcionId,
    String? oneSignalId,
    bool? usrProduccionIphone,
    String? usrFcmToken,
    String? usrApnsToken,
  });
}
