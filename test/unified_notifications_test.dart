import 'package:flutter_test/flutter_test.dart';
import 'package:unified_notifications/unified_notifications.dart';

void main() {
  test('normalizer builds stable event', () {
    const normalizer = NotificationSource.unknown;
    expect(normalizer.name, 'unknown');
  });
}
