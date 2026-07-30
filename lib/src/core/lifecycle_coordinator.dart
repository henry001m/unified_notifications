import 'dart:async';

import 'package:flutter/widgets.dart';

class LifecycleCoordinator with WidgetsBindingObserver {
  LifecycleCoordinator({
    required this.onResumed,
    required this.onBackgrounded,
    this.onInactive,
    this.onPaused,
    this.onDetached,
  });

  final Future<void> Function() onResumed;
  final Future<void> Function() onBackgrounded;
  final Future<void> Function()? onInactive;
  final Future<void> Function()? onPaused;
  final Future<void> Function()? onDetached;
  bool _registered = false;

  void register() {
    if (_registered) return;
    WidgetsBinding.instance.addObserver(this);
    _registered = true;
  }

  void dispose() {
    if (!_registered) return;
    WidgetsBinding.instance.removeObserver(this);
    _registered = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(onResumed());
        return;
      case AppLifecycleState.inactive:
        unawaited(onInactive?.call() ?? onBackgrounded());
        return;
      case AppLifecycleState.paused:
        unawaited(onPaused?.call() ?? onBackgrounded());
        return;
      case AppLifecycleState.hidden:
        unawaited(onBackgrounded());
        return;
      case AppLifecycleState.detached:
        unawaited(onDetached?.call() ?? onBackgrounded());
        return;
    }
  }
}
