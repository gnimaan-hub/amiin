// ─── Cartes affichées dans les bulles du chat ────────────────────────────────
// Note créée/modifiée, événement créé/modifié, confirmation de suppression.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../theme/colors.dart';
import '../theme/spacing.dart';
import '../theme/typography.dart';

// Carte cliquable affichée dans la bulle quand Amiin crée/modifie une note
class ChatNoteCard extends StatelessWidget {
  final String noteId;
  final String noteTitle;
  final String noteContent;
  final bool isUpdate;

  const ChatNoteCard({
    super.key,
    required this.noteId,
    required this.noteTitle,
    required this.noteContent,
    this.isUpdate = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/notes/$noteId'),
      child: Container(
        margin: const EdgeInsets.only(top: Spacing.sm),
        padding: const EdgeInsets.all(Spacing.sm + 2),
        decoration: BoxDecoration(
          color: ColorsAmiin.turquoiseLt,
          borderRadius: BorderRadius.circular(RadiusAmiin.md),
          border: Border.all(color: ColorsAmiin.turquoise.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: ColorsAmiin.turquoise.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isUpdate ? Icons.edit_note_outlined : Icons.note_outlined,
                color: ColorsAmiin.turquoiseDk,
                size: 18,
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isUpdate ? 'Note mise à jour' : 'Note créée',
                    style: TextStyle(
                      fontFamily: FontFamily.geoBold,
                      fontSize: 10,
                      color: ColorsAmiin.turquoiseDk,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    noteTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: FontFamily.geoMedium,
                      fontSize: 13,
                      color: ColorsAmiin.ink,
                    ),
                  ),
                  if (noteContent.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      noteContent,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: FontFamily.sans,
                        fontSize: 11,
                        color: ColorsAmiin.muted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: Spacing.sm),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 11,
              color: ColorsAmiin.turquoiseDk,
            ),
          ],
        ),
      ),
    );
  }
}

// Carte cliquable affichée dans la bulle quand Amiin crée/modifie un événement
class ChatEventCard extends StatelessWidget {
  final String eventId;
  final String eventTitle;
  final String eventDate; // ISO 8601
  final bool isUpdate;

  const ChatEventCard({
    super.key,
    required this.eventId,
    required this.eventTitle,
    required this.eventDate,
    this.isUpdate = false,
  });

  String get _formattedDate {
    try {
      return DateFormat('EEE d MMM · HH:mm', 'fr')
          .format(DateTime.parse(eventDate));
    } catch (_) {
      return eventDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.push('/agenda/event/$eventId'),
      borderRadius: BorderRadius.circular(RadiusAmiin.md),
      child: Container(
        margin: const EdgeInsets.only(top: Spacing.sm),
        padding: const EdgeInsets.all(Spacing.sm + 2),
        decoration: BoxDecoration(
          color: ColorsAmiin.turquoiseLt,
          borderRadius: BorderRadius.circular(RadiusAmiin.md),
          border: Border.all(color: ColorsAmiin.turquoise.withValues(alpha: 0.35)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: ColorsAmiin.turquoise.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isUpdate ? Icons.edit_calendar_outlined : Icons.event_outlined,
                color: ColorsAmiin.turquoise,
                size: 18,
              ),
            ),
            const SizedBox(width: Spacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isUpdate ? 'Événement mis à jour' : 'Événement créé',
                    style: TextStyle(
                      fontFamily: FontFamily.geoBold,
                      fontSize: 10,
                      color: ColorsAmiin.turquoise,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    eventTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: FontFamily.geoMedium,
                      fontSize: 13,
                      color: ColorsAmiin.ink,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    _formattedDate,
                    style: TextStyle(
                      fontFamily: FontFamily.sans,
                      fontSize: 11,
                      color: ColorsAmiin.muted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: Spacing.sm),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 11,
              color: ColorsAmiin.turquoise,
            ),
          ],
        ),
      ),
    );
  }
}

// Carte de confirmation : Amiin demande l'accord avant une suppression
class ChatDeleteConfirm extends StatelessWidget {
  final List<String> descriptions;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;

  const ChatDeleteConfirm({
    super.key,
    required this.descriptions,
    required this.onConfirm,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 36, top: 2, bottom: 4),
      padding: const EdgeInsets.symmetric(
          horizontal: Spacing.md, vertical: Spacing.sm),
      decoration: BoxDecoration(
        color: ColorsAmiin.white,
        borderRadius: BorderRadius.circular(RadiusAmiin.md),
        border: Border.all(color: const Color(0xFFD32F2F).withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 16, color: Color(0xFFD32F2F)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  descriptions.length == 1
                      ? 'Amiin souhaite supprimer : ${descriptions.first}'
                      : 'Amiin souhaite supprimer :\n${descriptions.map((d) => '• $d').join('\n')}',
                  style: TextStyle(
                    fontFamily: FontFamily.sans,
                    fontSize: 13,
                    color: ColorsAmiin.ink,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              _SuggestionBtn(
                  label: 'Supprimer', primary: true, onTap: onConfirm),
              const SizedBox(width: Spacing.sm),
              _SuggestionBtn(label: 'Annuler', primary: false, onTap: onDismiss),
            ],
          ),
        ],
      ),
    );
  }
}

// Chip de suggestion proactive : Amiin propose de créer une note
class ChatNoteSuggestion extends StatelessWidget {
  final String suggestionText;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;

  const ChatNoteSuggestion({
    super.key,
    required this.suggestionText,
    required this.onConfirm,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 36, right: 0, top: 2, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: Spacing.md, vertical: Spacing.sm),
      decoration: BoxDecoration(
        color: ColorsAmiin.white,
        borderRadius: BorderRadius.circular(RadiusAmiin.md),
        border: Border.all(color: ColorsAmiin.turquoise.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.note_add_outlined, size: 15, color: ColorsAmiin.turquoiseDk),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  suggestionText,
                  style: TextStyle(
                    fontFamily: FontFamily.sans,
                    fontSize: 13,
                    color: ColorsAmiin.ink,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Spacing.sm),
          Row(
            children: [
              _SuggestionBtn(label: 'Créer la note', primary: true, onTap: onConfirm),
              const SizedBox(width: Spacing.sm),
              _SuggestionBtn(label: 'Pas maintenant', primary: false, onTap: onDismiss),
            ],
          ),
        ],
      ),
    );
  }
}

class _SuggestionBtn extends StatelessWidget {
  final String label;
  final bool primary;
  final VoidCallback onTap;

  const _SuggestionBtn({
    required this.label,
    required this.primary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primary ? ColorsAmiin.turquoise : Colors.transparent,
      shape: StadiumBorder(
        side: BorderSide(
          color: primary ? ColorsAmiin.turquoise : ColorsAmiin.border,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: FontFamily.geoMedium,
              fontSize: 12,
              color: primary ? ColorsAmiin.white : ColorsAmiin.muted,
            ),
          ),
        ),
      ),
    );
  }
}

