import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

class FacteurLoader extends StatelessWidget {
  final double width;
  final double height;

  const FacteurLoader({
    super.key,
    this.width = 120,
    this.height = 120,
  });

  static const _asset = 'assets/loaders/loading_facteur.lottie';

  @override
  Widget build(BuildContext context) {
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
