import 'dart:convert';

import 'package:http/http.dart' as http;

import '../contracts/notificacion_service.dart';

class NotificacionServiceImpl implements NotificacionService {
  NotificacionServiceImpl({required this.baseUrl});

  final String baseUrl;
  static const String _subscriptionEndpoint =
      'api/notificacion/subscripcionUsuario';

  @override
  Future<void> subscripcionUsuario({
    String? subscripcionId,
    String? oneSignalId,
    bool? usrProduccionIphone,
    String? usrFcmToken,
    String? usrApnsToken,
  }) async {
    try {
      final json = <String, dynamic>{
        'usr_subscripcion_id': subscripcionId,
        'usr_onesignal_id': oneSignalId,
        if (usrProduccionIphone != null) 'usr_produccion_iphone': usrProduccionIphone,
        if (usrFcmToken != null) 'usr_fcm_token': usrFcmToken,
        if (usrApnsToken != null) 'usr_apns_token': usrApnsToken,
      };

      final url = Uri.parse('$baseUrl/$_subscriptionEndpoint');
      await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(json),
      );
    } catch (e) {
      // Log error but don't throw - notifications sync is non-critical
    }
  }
}
