// ─── NoteDetailScreen & CreateNoteScreen ─────────────────────────────────────

import 'package:flutter/material.dart';
import '../../widgets/amiin_svg_icons.dart';
import '../../widgets/horizon_line.dart';
import '../../widgets/toast.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../theme/themes.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/header.dart';
import '../../widgets/tag.dart';
import '../../services/notes_service.dart';

// ── Écran de création de note ───────────────────────────────────────────────
class CreateNoteScreen extends StatefulWidget {
  const CreateNoteScreen({super.key});

  @override
  State<CreateNoteScreen> createState() => _CreateNoteScreenState();
}

class _CreateNoteScreenState extends State<CreateNoteScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _tagInputController = TextEditingController();
  final List<String> _tags = [];

  void _addTag() {
    final t = _tagInputController.text.trim().toLowerCase();
    if (t.isNotEmpty && !_tags.contains(t)) {
      setState(() => _tags.add(t));
      _tagInputController.clear();
    }
  }

  void _removeTag(String tag) {
    setState(() => _tags.remove(tag));
  }

  Future<void> _save() async {
    if (_titleController.text.trim().isEmpty) {
      AmiinToast.show(context, 'Le titre est requis.', success: false);
      return;
    }
    if (_contentController.text.trim().isEmpty) {
      AmiinToast.show(context, 'Le contenu ne peut pas être vide.', success: false);
      return;
    }
    try {
      await notesService.createNote(CreateNotePayload(
        title: _titleController.text.trim(),
        content: _contentController.text.trim(),
        tags: _tags.isNotEmpty ? _tags : null,
      ));
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        AmiinToast.show(context, e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.ac.background,
      body: SafeArea(
        child: Column(
          children: [
            AmiinHeader(
              mode: AmiinMode.secretariat,
              title: 'Nouvelle note',
              back: true,
              rightAction: IconButton(
                icon: SvgPicture.string(AmiinSvgIcons.check, width: 22, height: 22),
                onPressed: _save,
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Spacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _titleController,
                      style: TextStyle(fontFamily: FontFamily.geo, fontSize: 22, color: context.ac.ink),
                      decoration: InputDecoration(
                        hintText: 'Titre',
                        border: UnderlineInputBorder(borderSide: BorderSide(color: context.ac.border)),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: context.ac.secretariatAccent)),
                      ),
                    ),
                    const SizedBox(height: Spacing.lg),
                    TextField(
                      controller: _contentController,
                      maxLines: null,
                      style: TextStyle(fontFamily: FontFamily.sans, fontSize: 15, color: context.ac.ink, height: 1.5),
                      decoration: const InputDecoration(
                        hintText: 'Écrivez votre note ici…',
                        border: InputBorder.none,
                      ),
                    ),
                    const SizedBox(height: Spacing.lg),
                    Text('Tags', style: TextStyle(
                      fontFamily: FontFamily.geoBold,
                      fontSize: 10,
                      letterSpacing: 1.2,
                      color: context.ac.muted,
                    )),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: Spacing.sm,
                      runSpacing: Spacing.sm,
                      children: _tags.map((t) => GestureDetector(
                        onTap: () => _removeTag(t),
                        child: AmiinTag(label: '$t ×', variant: TagVariant.turquoise),
                      )).toList(),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _tagInputController,
                            onSubmitted: (_) => _addTag(),
                            decoration: InputDecoration(
                              hintText: 'Ajouter un tag…',
                              border: OutlineInputBorder(borderSide: BorderSide(color: context.ac.border)),
                              contentPadding: EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: Spacing.sm),
                        GestureDetector(
                          onTap: _addTag,
                          child: Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(color: context.ac.secretariatAccent, borderRadius: BorderRadius.all(Radius.circular(RadiusAmiin.sm))),
                            child: Center(child: Text('+', style: TextStyle(fontSize: 22, color: context.ac.onAccent))),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}

// ── Écran de détail / modification ───────────────────────────────────────────
class NoteDetailScreen extends StatefulWidget {
  final String noteId;
  const NoteDetailScreen({super.key, required this.noteId});

  @override
  State<NoteDetailScreen> createState() => _NoteDetailScreenState();
}

class _NoteDetailScreenState extends State<NoteDetailScreen> {
  AmiinNote? _note;
  bool _loading = true;
  bool _editing = false;
  late TextEditingController _titleController;
  late TextEditingController _contentController;
 

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _contentController = TextEditingController();
    _loadNote();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  Future<void> _loadNote() async {
    try {
      final n = await notesService.getNote(widget.noteId);
      if (mounted) {
        _titleController.text = n.title;
        _contentController.text = n.content;
        setState(() {
          _note = n;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        AmiinToast.show(context, 'Impossible de charger la note.');
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save() async {
    if (_note == null) return;
    if (_titleController.text.trim().isEmpty) {
      AmiinToast.show(context, 'Le titre est requis.', success: false);
      return;
    }
    if (_contentController.text.trim().isEmpty) {
      AmiinToast.show(context, 'Le contenu ne peut pas être vide.', success: false);
      return;
    }
    try {
      final updated = await notesService.updateNote(_note!.id, {
        'title': _titleController.text.trim(),
        'content': _contentController.text.trim(),
      });
      if (mounted) {
        setState(() {
          _note = updated;
          _editing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        AmiinToast.show(context, e.toString());
      }
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer'),
        content: const Text('Êtes-vous sûr de vouloir supprimer cette note ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(context, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Supprimer')),
        ],
      ),
    );
    if (confirm == true) {
      await notesService.deleteNote(widget.noteId);
      if (mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(body: Center(child: CircularProgressIndicator(color: context.ac.secretariatAccent)));
    }
    if (_note == null) return const SizedBox();

    return Scaffold(
      backgroundColor: context.ac.background,
      body: SafeArea(
        child: Column(
          children: [
            AmiinHeader(
              mode: AmiinMode.secretariat,
              title: _editing ? 'Modifier' : 'Note',
              back: true,
              rightAction: _editing
                  ? IconButton(
                      icon: SvgPicture.string(AmiinSvgIcons.check, width: 22, height: 22),
                      onPressed: _save,
                    )
                  : IconButton(
                      icon: SvgPicture.string(AmiinSvgIcons.edit, width: 20, height: 20),
                      onPressed: () => setState(() => _editing = true),
                    ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Spacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _editing
                      ? [
                          TextField(
                            controller: _titleController,
                            style: TextStyle(fontFamily: FontFamily.geo, fontSize: 22, color: context.ac.ink),
                            decoration: const InputDecoration(border: InputBorder.none),
                          ),
                          const SizedBox(height: Spacing.md),
                          TextField(
                            controller: _contentController,
                            maxLines: null,
                            style: TextStyle(fontFamily: FontFamily.sans, fontSize: 15, color: context.ac.ink, height: 1.5),
                            decoration: const InputDecoration(border: InputBorder.none),
                          ),
                        ]
                      : [
                          Text(_note!.title, style: TextStyle(
                            fontFamily: FontFamily.geo,
                            fontSize: 24,
                            color: context.ac.ink,
                            height: 1.2,
                          )),
                          const SizedBox(height: 8),
                          Text(
                            'Modifié le ${DateFormat('d MMMM yyyy', 'fr').format(DateTime.parse(_note!.updatedAt))}${_note!.createdByAgent == true ? ' · Créé par Amiin' : ''}',
                            style: TextStyle(fontFamily: FontFamily.sans, fontSize: 11, color: context.ac.muted),
                          ),
                          const SizedBox(height: 12),
                          if (_note!.tags.isNotEmpty)
                            Wrap(
                              spacing: Spacing.sm,
                              runSpacing: Spacing.sm,
                              children: _note!.tags.map((t) => AmiinTag(label: t)).toList(),
                            ),
                          const SizedBox(height: Spacing.lg),
                          Text(_note!.content, style: TextStyle(
                            fontFamily: FontFamily.sans,
                            fontSize: 15,
                            color: context.ac.ink,
                            height: 1.5,
                          )),
                          if (_note!.agentContext != null) ...[
                            const SizedBox(height: Spacing.lg),
                            Container(
                              padding: const EdgeInsets.all(Spacing.md),
                              decoration: BoxDecoration(
                                color: context.ac.secretariatAccentLight,
                                borderRadius: BorderRadius.circular(RadiusAmiin.md),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Contexte Amiin', style: TextStyle(
                                    fontFamily: FontFamily.geoBold,
                                    fontSize: 10,
                                    letterSpacing: 1.2,
                                    color: context.ac.secretariatAccentDark,
                                  )),
                                  const SizedBox(height: 6),
                                  Text(_note!.agentContext!, style: TextStyle(
                                    fontFamily: FontFamily.sans,
                                    fontSize: 13,
                                    color: context.ac.secretariatAccentDark,
                                    height: 1.4,
                                  )),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: Spacing.xxl),
                          Center(
                            child: TextButton(
                              onPressed: _delete,
                              child: Text('Supprimer cette note', style: TextStyle(color: context.ac.muted)),
                            ),
                          ),
                        ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}

