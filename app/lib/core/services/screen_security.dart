import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Screenshot / screen-recording protection.
///
/// * **Android** — `FLAG_SECURE` is applied natively in `MainActivity`
///   before the first frame, so screenshots, screen recordings, casting and
///   the recent-apps thumbnail all show a black screen.
/// * **iOS** — iOS doesn't allow blocking screenshots, so the native side
///   renders the app inside a secure layer (captures come out blank) and
///   reports screen recording / mirroring through this channel; while it is
///   active [ScreenSecurityShield] covers the UI.
class ScreenSecurity {
  ScreenSecurity._();
  static final instance = ScreenSecurity._();

  static const _channel = MethodChannel('io.prostuti.app/screen_security');

  final captured = ValueNotifier<bool>(false);

  Future<void> init() async {
    if (kIsWeb) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'captureChanged') captured.value = call.arguments == true;
    });
    try {
      final initial = await _channel.invokeMethod<bool>('isCaptured');
      captured.value = initial ?? false;
    } on MissingPluginException {
      // Android handles everything natively; nothing to observe.
    } on PlatformException {
      // ignore
    }
  }
}

/// Covers the app while the screen is being recorded or mirrored (iOS).
class ScreenSecurityShield extends StatelessWidget {
  const ScreenSecurityShield({required this.child, super.key});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ScreenSecurity.instance.captured,
      child: child,
      builder: (context, captured, child) => Stack(
        children: [
          child!,
          if (captured)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0xFF0F1513),
                child: Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.screen_lock_portrait_rounded, color: Colors.white70, size: 56),
                        SizedBox(height: 16),
                        Text(
                          'স্ক্রিন রেকর্ডিং চলাকালীন কনটেন্ট দেখানো হয় না',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white, fontSize: 16, fontFamily: 'HindSiliguri'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
