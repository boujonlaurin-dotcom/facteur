import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../config/theme.dart';
import '../../../widgets/design/facteur_logo.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(
        title: const Text('Présentation Facteur'),
        backgroundColor: colors.backgroundPrimary,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(FacteurSpacing.space6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: FacteurSpacing.space8),
                child: FacteurLogo(size: 40),
              ),
            ),
            _buildSection(
              context,
              title: 'Le Projet',
              content:
                  'Facteur est un projet open-source visant à créer une brique engageante et facile d\'accès pour s\'approprier l\'information. Nous pensons que la technologie doit servir l\'humanité - pas l\'inverse.',
            ),
            const SizedBox(height: FacteurSpacing.space6),
            _buildSection(
              context,
              title: 'Notre But',
              content:
                  'Re-donner de la qualité, de l\'indépendance et de la pluralité à l\'information. Dans un monde qui déborde d\'informations, nous visons à trier l\'info du bruit pour informer en profondeur.',
            ),
            const SizedBox(height: FacteurSpacing.space6),
            _buildSection(
              context,
              title: 'Philosophie',
              content:
                  'Nous avançons pas-à-pas. Notre approche consiste à créer d\'abord une communauté de profils déjà sensibilisés aux enjeux de l\'information, pour ensuite élargir l\'impact du projet et toucher un public plus vaste.\n \n Nous cherchons des contributeurs pour enrichir le projet et l\'ouvrir à tous. Rejoignez-nous !',
            ),
            const SizedBox(height: FacteurSpacing.space8),
            Text(
              'Nos Combats',
              style: GoogleFonts.fraunces(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: FacteurSpacing.space4),
            _buildCombatItem(
              context,
              icon: Icons.business_outlined,
              title: 'Anti-trust des médias',
              description:
                  'Lutter contre la concentration des médias entre les mains de quelques milliardaires.',
            ),
            _buildCombatItem(
              context,
              icon: Icons.psychology_outlined,
              title: 'Biais cognitifs',
              description:
                  'Aider nos cerveaux à moins tomber dans nos biais naturels face à l\'information.',
            ),
            _buildCombatItem(
              context,
              icon: Icons.code_off_outlined,
              title: 'Algorithmes opaques',
              description:
                  'S\'opposer à la dictature des algorithmes de recommandation qui enferment dans des bulles.',
            ),
            _buildCombatItem(
              context,
              icon: Icons.phonelink_erase_outlined,
              title: 'Addiction numérique',
              description:
                  'Réduire les mécanismes addictifs liés à la consommation d\'interfaces et d\'informations.',
            ),
            const SizedBox(height: FacteurSpacing.space8),
            Center(
              child: Text(
                'Version 1.0.0 • Open Source',
                style:
                    textTheme.labelSmall?.copyWith(color: colors.textTertiary),
              ),
            ),
            const SizedBox(height: FacteurSpacing.space8),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context,
      {required String title, required String content}) {
    final colors = context.facteurColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.fraunces(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: FacteurSpacing.space2),
        Text(
          content,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
                height: 1.6,
              ),
        ),
      ],
    );
  }

  Widget _buildCombatItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: FacteurSpacing.space4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(FacteurSpacing.space2),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(FacteurRadius.small),
            ),
            child: Icon(icon, color: colors.primary, size: 20),
          ),
          const SizedBox(width: FacteurSpacing.space4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                ),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
