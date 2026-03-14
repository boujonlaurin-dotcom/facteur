import 'package:flutter/material.dart';

/// Editorial intro text displayed above each topic section (N1).
/// Shows 2-3 LLM-generated sentences introducing the topic.
class IntroText extends StatelessWidget {
  final String text;

  const IntroText({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF2C1E10);

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 12),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w400,
          height: 1.5,
          color: textColor,
        ),
      ),
    );
  }
}
