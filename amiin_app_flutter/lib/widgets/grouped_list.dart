// ─── GroupedList ─────────────────────────────────────────────────────────────
// Liste groupée « vitrine » : plusieurs lignes dans une seule carte
// flottante, séparées par de fins traits décalés pour s'aligner sur le texte.
// Référence : docs/REFONTE_VITRINE.md (étape 14).

import 'package:flutter/material.dart';
import '../theme/spacing.dart';
import '../theme/themes.dart';
import 'floating_card.dart';

class GroupedList extends StatelessWidget {
  final List<Widget> children;

  /// Décalage à gauche des séparateurs (aligné sur le début du texte).
  final double dividerIndent;

  const GroupedList({
    super.key,
    required this.children,
    this.dividerIndent = Spacing.lg,
  });

  @override
  Widget build(BuildContext context) {
    final ac = context.ac;
    return FloatingCard(
      padding: EdgeInsets.zero,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: EdgeInsets.only(left: dividerIndent),
                  child: Divider(
                    height: 0.5,
                    thickness: 0.5,
                    color: ac.border.withValues(alpha: 0.7),
                  ),
                ),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}
