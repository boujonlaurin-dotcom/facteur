import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../../config/theme.dart';

class FacteurLoader extends StatelessWidget {
  final double width;
  final double height;
  final Color? color;

  const FacteurLoader({
    super.key,
    this.width = 120,
    this.height = 120,
    this.color,
  });

  static const _asset = 'assets/loaders/loading_facteur.json';

  @override
  Widget build(BuildContext context) {
    final tint = color ?? context.facteurColors.primary;
    if (kIsWeb) {
      // Lottie repaints every frame — kills Safari iOS scroll/idle perf.
      // Static spinner is enough for the temporary web build.
      final dim = width < height ? width : height;
      final stroke = (dim / 14).clamp(2.0, 4.0).toDouble();
      return SizedBox(
        width: width,
        height: height,
        child: Center(
          child: SizedBox(
            width: dim * 0.5,
            height: dim * 0.5,
            child: CircularProgressIndicator(
              strokeWidth: stroke,
              valueColor: AlwaysStoppedAnimation<Color>(tint),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: width,
      height: height,
      child: Lottie.asset(
        _asset,
        fit: BoxFit.contain,
        repeat: true,
        delegates: LottieDelegates(
          values: [
            ValueDelegate.color(const ['**'], value: tint),
            ValueDelegate.strokeColor(const ['**'], value: tint),
          ],
        ),
        frameBuilder: (context, child, composition) {
          if (composition == null) {
            return SizedBox(width: width, height: height);
          }
          return child;
        },
      ),
    );
  }
}
