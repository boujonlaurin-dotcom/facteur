import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../models/weather_snapshot.dart';

/// SVG météo artistique + badge émoji condition superposé en bas-à-droite.
class WeatherConditionIcon extends StatelessWidget {
  final WeatherCondition condition;
  final double size;
  final double badgeSize;
  final double emojiSize;
  final double badgeInset;

  const WeatherConditionIcon({
    super.key,
    required this.condition,
    required this.size,
    this.badgeSize = 28,
    this.emojiSize = 17,
    this.badgeInset = 5,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SvgPicture.asset(
          'assets/images/weather/${condition.assetName}.svg',
          width: size,
          height: size,
        ),
        Positioned(
          bottom: badgeInset,
          right: badgeInset,
          child: Container(
            width: badgeSize,
            height: badgeSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 6,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Text(
              _emoji(condition),
              style: TextStyle(fontSize: emojiSize, height: 1),
            ),
          ),
        ),
      ],
    );
  }
}

String _emoji(WeatherCondition condition) {
  switch (condition) {
    case WeatherCondition.sunny:
      return '☀️';
    case WeatherCondition.partlyCloudy:
      return '⛅';
    case WeatherCondition.cloudy:
      return '☁️';
    case WeatherCondition.rainy:
      return '🌧️';
    case WeatherCondition.snowy:
      return '❄️';
  }
}
