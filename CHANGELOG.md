## 1.0.0

### Alignment with production notification systems

This release aligns the library with the production notification systems of
`boeindustryapperp` (AppERP) and `BoeIndustryFrontendTareasAPP` (Tareas),
both running Flutter + FCM + APNs + EMQX.

### Removed
- OneSignal integration: removed `onesignal_flutter` dependency,
  `OneSignalBridge`, config `enableOneSignal`/`oneSignalAppId`, and all
  related exports. The library now handles only FCM, APNs and EMQX.
- `bridges/onesignal/` directory (was empty).

### Changed files (15 files)

| File | Change |
|------|--------|
| `pubspec.yaml` | Removed `onesignal_flutter: ^5.3.5`, added `flutter_background_service_android: ^6.3.0` |
| `lib/unified_notifications.dart` | Removed OneSignal exports, added `background_notification_service` exports |
| `lib/src/config/unified_notification_config.dart` | Removed `enableOneSignal`, `oneSignalAppId`. Added `foregroundServiceNotificationId`, `foregroundServiceNotificationTitle`, `foregroundServiceNotificationContent` |
| `lib/src/storage/notification_store_keys.dart` | Added keys: `notificationTopicBase`, `showSystemNotificationsKey`, `pendingQueue`, `displayedIdsByGroup`, `recentlyDeliveredEventIds` (matching production keys) |
| `lib/src/bridges/fcm/fcm_bridge.dart` | Added `_pendingReceived`/`_pendingOpened` queues, `takePendingReceived()`/`takePendingOpened()`, remote message logging matching production, removed unused imports |
| `lib/src/bridges/apns/apns_bridge.dart` | Added `obtenerEntornoApns()`, `esEntornoProduccion()`, `_ApnsLifecycleObserver`, retry with 3 attempts, `onApnsRegistrationFailed` handler |
| `lib/src/bridges/mqtt/mqtt_bridge.dart` | Added automatic reconnection with backoff, `onConnected`/`onDisconnected` callbacks, `pongCallback`, logging throughout |
| `lib/src/bridges/fcm/fcm_background_handler.dart` | Rewrote to match production FCM background handler: deduplication via `SharedPreferences` (`recentlyDeliveredEventIds` with 10min window), nested data extraction, pending queue + inbox persistence |
| `lib/src/core/notification_normalizer.dart` | Rewrote to match `normalizeNotificationPayload()` from both apps: `_resolveEventId()`, `_resolveGroupKey()`, `_extractAdditionalData()`, `_extractEntityIds()` (mk_id, sp_id, ti_id, etc.), `_extractSound()` with APS support |
| `lib/src/render/local_notification_renderer.dart` | Rewrote to match `showEmqxLocalNotification()`: dynamic Android channels per sound, `_resolveAndroidSoundName()`/`_resolveIosSoundName()` with `_availableCustomSounds`, Android group summaries, `_tryReserveEventId()` dedup, `_persistDisplayedNotificationId()`/`_readDisplayedNotificationRegistry()`, per-channel delivery channels |
| `lib/src/sdk/notification_runtime.dart` | Added `BackgroundNotificationService` integration, `LifecycleCoordinator` (disconnect MQTT on background, reconnect + drain on resume), `_startBackgroundService()`, dual pending queue drain (background + store) |
| `lib/src/sdk/unified_notifications.dart` | Removed `OneSignalBridge`/`oneSignalBridge`, updated `init()` to initialise `BackgroundNotificationService`, fixed `NotificationStore` import, removed unused import |
| `lib/src/sdk/background_notification_service.dart` | **New file**: Background MQTT runtime in separate isolate — mirrors `_BackgroundNotificationRuntime` from both apps. Handles `connectUser`/`disconnectUser`/`ackNotification` via service events, pending queue in SharedPreferences, dedup by `recentlyDeliveredEventIds`, local notification rendering in background. Entry point: `unifiedNotificationsBackgroundEntryPoint` |
| `lib/src/router/default_notification_router.dart` | Extended route map to 40+ routes combining both apps: added `atencionsoportespark`, `chatatencionsoportespark`, `atencionsoporte`, `chatatencionsoporte`, `chatAsignarProducto`, etc. |
| `lib/src/render/android_channel_manager.dart` | Removed unsupported `priority` parameter from `ensureChannel()` |

### Architecture

```
main isolate                        background isolate
┌──────────────────────┐            ┌───────────────────────────┐
│  FcmBridge           │            │  _BackgroundMqttRuntime   │
│  ApnsBridge          │            │  - MQTT client            │
│  MqttBridge (UI)     │            │  - Pending queue (SP)     │
│         │            │            │  - Local notifications    │
│         ▼            │            │  - Dedup (10min window)   │
│  NotificationRuntime │◄───────────│  - Service events         │
│  - dedup             │  events    └───────────────────────────┘
│  - lifecycle mgmt    │
│  - background bridge │
│  - store + render    │
└──────────────────────┘
```

### Key behaviours preserved from production
- FCM `onMessage` / `onMessageOpenedApp` / `getInitialMessage` with nested data extraction
- APNs MethodChannel `app.notificaciones/apns` with pending event consumption
- EMQX MQTT topic subscription per server region
- 10-minute deduplication window via `recentlyDeliveredEventIds`
- Android notification channels per custom sound
- Android group summary notifications
- Background service with separate MQTT isolate
- Lifecycle-aware connect/disconnect
- Pending notification queue drained on init/resume
