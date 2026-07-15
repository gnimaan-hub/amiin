// ─── SettingsBillingScreen ────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../../theme/themes.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/header.dart';
import '../../widgets/card.dart';
import 'settings_widgets.dart';

class SettingsBillingScreen extends StatelessWidget {
  const SettingsBillingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: context.ac.background,
      body: SafeArea(
        child: Column(
          children: [
            const AmiinHeader(title: 'Facturation', back: true),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Spacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: Spacing.sm),

                    // ── Plan actuel ───────────────────────────────────────
                    AmiinCard(
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: Spacing.xs),
                                decoration: BoxDecoration(
                                  color: primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(RadiusAmiin.xl),
                                ),
                                child: Text('GRATUIT', style: TextStyle(
                                  fontFamily: FontFamily.geoBold,
                                  fontSize: 11,
                                  letterSpacing: 0.8,
                                  color: primary,
                                )),
                              ),
                              const Spacer(),
                              Icon(Icons.star_outline, color: primary, size: 20),
                            ],
                          ),
                          const SizedBox(height: Spacing.md),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Plan Amiin Gratuit',
                              style: TextStyle(
                                fontFamily: FontFamily.geoBold,
                                fontSize: 18,
                                color: context.ac.ink,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Accès aux fonctionnalités essentielles',
                              style: TextStyle(
                                fontFamily: FontFamily.sans,
                                fontSize: 13,
                                color: context.ac.muted,
                              ),
                            ),
                          ),
                          const SizedBox(height: Spacing.lg),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            decoration: BoxDecoration(
                              color: primary,
                              borderRadius: BorderRadius.circular(RadiusAmiin.lg),
                            ),
                            child: const Text(
                              'Passer à Amiin Pro — Bientôt disponible',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontFamily: 'DM Sans',
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SettingsSection('Abonnement'),
                    SettingCard(children: [
                      SettingRow(
                        icon: Icons.receipt_long_outlined,
                        label: 'Historique de paiement',
                        onTap: () => _stub(context),
                      ),
                      SettingRow(
                        icon: Icons.card_giftcard_outlined,
                        label: 'Code promotionnel',
                        onTap: () => _showPromoDialog(context),
                      ),
                      SettingRow(
                        icon: Icons.manage_accounts_outlined,
                        label: 'Gérer l\'abonnement',
                        subtitle: 'Modifier, annuler, changer de plan',
                        onTap: () => _stub(context),
                      ),
                    ]),

                    const SizedBox(height: Spacing.xxxl),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _stub(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Facturation disponible prochainement'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showPromoDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Code promotionnel'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: 'Entrez votre code'),
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Fonctionnalité bientôt disponible')),
              );
            },
            child: const Text('Appliquer'),
          ),
        ],
      ),
    );
  }
}

