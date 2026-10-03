import 'package:flutter/widgets.dart';

/// 4-pt spacing scale. Use these instead of magic numbers.
abstract final class Gap {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;

  static const h4 = SizedBox(height: xs);
  static const h8 = SizedBox(height: sm);
  static const h12 = SizedBox(height: md);
  static const h16 = SizedBox(height: lg);
  static const h24 = SizedBox(height: xl);
  static const h32 = SizedBox(height: xxl);
  static const w4 = SizedBox(width: xs);
  static const w8 = SizedBox(width: sm);
  static const w12 = SizedBox(width: md);
  static const w16 = SizedBox(width: lg);

  static const screen = EdgeInsets.symmetric(horizontal: lg);
  static const card = EdgeInsets.all(lg);
}

abstract final class Radii {
  static const sm = Radius.circular(8);
  static const md = Radius.circular(12);
  static const lg = Radius.circular(16);
  static const xl = Radius.circular(24);

  static const card = BorderRadius.all(lg);
  static const button = BorderRadius.all(md);
  static const chip = BorderRadius.all(Radius.circular(100));
}
