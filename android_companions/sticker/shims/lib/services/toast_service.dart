import 'package:flutter/material.dart';
import 'local_notification_service.dart';

abstract final class ToastService {
  static void showSuccess(String message) {
    final context = navigatorKey.currentContext;
    if (context == null) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
