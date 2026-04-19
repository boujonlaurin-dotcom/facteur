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
