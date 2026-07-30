import '../contracts/notification_router.dart';
import '../models/unified_notification_event.dart';

class DefaultNotificationRouter implements NotificationRouter {
  const DefaultNotificationRouter();

  static const Map<String, String> _defaultRouteMap = {
    // Ventas
    'detalleNotaVenta': 'informacionResumenVenta',
    'resumennotaventacuentabanco': 'resumenSeguimientoVenta',
    'resumenpedidopreparar': 'detalleNotaVentaCreditoProcesoSeguimiento',
    'detallePreparadoMercaderia': 'pedidoAPrepararDetalle',
    'detallePedidosPreparados': 'pedidoPreparadoDetalle',
    'detallePedidoNacional': 'seguimientoEnvio',

    // Garantías
    'detalleGarantiaIngreso': 'detalleGarantiaIngreso',

    // Cupones / Wallet / BoeCoins
    'detallCupon': 'tusCupones',
    'detalleWallet': 'wallet',
    'detalleWalletDescuento': 'descuentoWallet',
    'detallBoeCoin': 'boeCoins',

    // Pagos
    'detalleQrPago': 'aprobarPagoContabilidad',

    // Reclamos
    'reclamocliente': 'chatReclamo',
    'reclamo': 'chatReclamo',

    // Cuentas / Transferencias
    'cuentaPersona': 'resumenEntregaDeDineroCajaPersona',
    'cuentaBanco': 'resumenEntregaDeDineroCajaBanco',
    'detalleTransferenciaCuentaCripto':
        'detalleTransferenciaDineroCuentaCripto',
    'detalleTransferenciaCuentaBanco':
        'detalleTransferenciaDineroCuentaBanco',
    'detalleTransferenciaCuentaPersona': 'detalleTransferenciaDineroCuenta',
    'resumenTransferenciaCuentaBanco': 'resumenMovimientoCuentaBanco',
    'resumenTransferenciaCuentaPersona': 'resumenMovimientoCuentaPersona',
    'gastoFijoResumen': 'resumenGastoFijoCuentasBanco',
    'resumenEntregaDineroCentroCostoPersona':
        'resumenEntregaDineroCentroCosto',
    'resumenEntregaDineroCentroCostoBanco':
        'resumenEntregaDineroCentroCosto',

    // Marketing / Tareas
    'chatmarketingspark': 'detalleTareaMarketingUnificada',
    'asignartareaspark': 'detalleTareaMarketingUnificada',
    'asignartareainterna': 'detalleTareaInterna',

    // Soporte
    'chatsoportespark': 'detalleSoporte',
    'asignarsoportespark': 'detalleSoporte',
    'atencionsoportespark': 'detalleSoporte',
    'chatatencionsoportespark': 'detalleSoporte',
    'atencionsoporte': 'detalleSoporte',
    'chatatencionsoporte': 'detalleSoporte',
    'atencionGeneral': 'atencionGeneralChat',

    // Productos
    'misProductosAsignados': 'misProductosAsignados',
    'chatAsignarProducto': 'chatAsignarProducto',

    // WhatsApp
    'whatsappmensaje': 'chat',

    // Sistema
    'cierreSesion': 'cierreSesion',
  };

  @override
  Map<String, String> get routeMap => _defaultRouteMap;

  @override
  Future<void> handle(UnifiedNotificationEvent event) async {
    if (event.route == null || event.route!.isEmpty) return;

    final screen = _defaultRouteMap[event.route!];
    if (screen != null) {
      // Override in subclasses to handle actual navigation
    }
  }

  String? resolveScreen(String route) {
    return _defaultRouteMap[route];
  }
}
