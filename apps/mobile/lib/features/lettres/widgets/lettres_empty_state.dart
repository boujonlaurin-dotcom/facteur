import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';

class LettresEmptyState extends StatelessWidget {
  const LettresEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0, -1),
          radius: 0.6,
          colors: [
            colors.textPrimary.withOpacity(0.04),
            colors.backgroundPrimary,
          ],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 200,
                height: 180,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFF8F0DD),
                ),
                clipBehavior: Clip.antiAlias,
                child: Opacity(
                  opacity: 0.92,
                  child: Image.asset(
                    'assets/notifications/facteur_avatar.png',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Rien à déposer aujourd’hui.',
                style: GoogleFonts.fraunces(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                  color: colors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: Text(
                  'Le Facteur reviendra bientôt avec une nouvelle lettre.',
                  style: GoogleFonts.fraunces(
                    fontSize: 14.5,
                    fontStyle: FontStyle.italic,
                    height: 1.4,
                    color: colors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
