import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../../../config/theme.dart';

class FacteurLoader extends StatelessWidget {
  final double width;
  final double height;
  final Color? color;

  const FacteurLoader({
    super.key,
    this.width = 160,
    this.height = 160,
    this.color,
  });

  static const _asset = 'assets/loaders/loading_facteur.lottie';

  @override
  Widget build(BuildContext context) {
    final tint = color ?? context.facteurColors.primary;
    return SizedBox(
      width: width,
      height: height,
      child: Lottie.asset(
        _asset,
        decoder: (bytes) => LottieComposition.decodeZip(
          bytes,
          filePicker: (files) => files.firstWhere(
            (f) => f.name.endsWith('.json') && f.name != 'manifest.json',
          ),
        ),
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
