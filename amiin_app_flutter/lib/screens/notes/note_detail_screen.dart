// ─── NoteDetailScreen & CreateNoteScreen ─────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../theme/colors.dart';
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Le titre est requis.'), backgroundColor: ColorsAmiin.turquoise),
      );
      return;
    }
    if (_contentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Le contenu ne peut pas être vide.'), backgroundColor: ColorsAmiin.turquoise),
      );
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ColorsAmiin.ecru,
      body: SafeArea(
        child: Column(
          children: [
            AmiinHeader(
              title: 'Nouvelle note',
              back: true,
              rightAction: IconButton(
                icon: SvgPicture.string(_checkSvg, width: 22, height: 22),
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
                      style: TextStyle(fontFamily: FontFamily.geo, fontSize: 22, color: ColorsAmiin.ink),
                      decoration: const InputDecoration(
                        hintText: 'Titre',
                        border: UnderlineInputBorder(borderSide: BorderSide(color: ColorsAmiin.border)),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: ColorsAmiin.turquoise)),
                      ),
                    ),
                    const SizedBox(height: Spacing.lg),
                    TextField(
                      controller: _contentController,
                      maxLines: null,
                      style: TextStyle(fontFamily: FontFamily.sans, fontSize: 15, color: ColorsAmiin.ink, height: 1.5),
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
                      color: ColorsAmiin.muted,
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
                            decoration: const InputDecoration(
                              hintText: 'Ajouter un tag…',
                              border: OutlineInputBorder(borderSide: BorderSide(color: ColorsAmiin.border)),
                              contentPadding: EdgeInsets.symmetric(horizontal: Spacing.md, vertical: 10),
                            ),
                          ),
                        ),
                        const SizedBox(width: Spacing.sm),
                        GestureDetector(
                          onTap: _addTag,
                          child: Container(
                            width: 40, height: 40,
                            decoration: const BoxDecoration(color: ColorsAmiin.turquoise, borderRadius: BorderRadius.all(Radius.circular(RadiusAmiin.sm))),
                            child: const Center(child: Text('+', style: TextStyle(fontSize: 22, color: ColorsAmiin.white))),
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

  static const String _checkSvg = '''
    <svg width="22" height="22" viewBox="0 0 22 22" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path d="M4 12l5 5 9-10" stroke="#B85530" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>
  ''';
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Impossible de charger la note.')));
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save() async {
    if (_note == null) return;
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Le titre est requis.'), backgroundColor: ColorsAmiin.turquoise),
      );
      return;
    }
    if (_contentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Le contenu ne peut pas être vide.'), backgroundColor: ColorsAmiin.turquoise),
      );
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
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
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: ColorsAmiin.turquoise)));
    }
    if (_note == null) return const SizedBox();

    return Scaffold(
      backgroundColor: ColorsAmiin.ecru,
      body: SafeArea(
        child: Column(
          children: [
            AmiinHeader(
              title: _editing ? 'Modifier' : 'Note',
              back: true,
              rightAction: _editing
                  ? IconButton(
                      icon: SvgPicture.string(_checkSvg, width: 22, height: 22),
                      onPressed: _save,
                    )
                  : IconButton(
                      icon: SvgPicture.string(_editSvg, width: 20, height: 20),
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
                            style: TextStyle(fontFamily: FontFamily.geo, fontSize: 22, color: ColorsAmiin.ink),
                            decoration: const InputDecoration(border: InputBorder.none),
                          ),
                          const SizedBox(height: Spacing.md),
                          TextField(
                            controller: _contentController,
                            maxLines: null,
                            style: TextStyle(fontFamily: FontFamily.sans, fontSize: 15, color: ColorsAmiin.ink, height: 1.5),
                            decoration: const InputDecoration(border: InputBorder.none),
                          ),
                        ]
                      : [
                          Text(_note!.title, style: TextStyle(
                            fontFamily: FontFamily.geo,
                            fontSize: 24,
                            color: ColorsAmiin.ink,
                            height: 1.2,
                          )),
                          const SizedBox(height: 8),
                          Text(
                            'Modifié le ${DateFormat('d MMMM yyyy', 'fr').format(DateTime.parse(_note!.updatedAt))}${_note!.createdByAgent == true ? ' · Créé par Amiin' : ''}',
                            style: TextStyle(fontFamily: FontFamily.sans, fontSize: 11, color: ColorsAmiin.muted),
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
                            color: ColorsAmiin.ink,
                            height: 1.5,
                          )),
                          if (_note!.agentContext != null) ...[
                            const SizedBox(height: Spacing.lg),
                            Container(
                              padding: const EdgeInsets.all(Spacing.md),
                              decoration: BoxDecoration(
                                color: ColorsAmiin.turquoiseLt,
                                borderRadius: BorderRadius.circular(RadiusAmiin.md),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Contexte Amiin', style: TextStyle(
                                    fontFamily: FontFamily.geoBold,
                                    fontSize: 10,
                                    letterSpacing: 1.2,
                                    color: ColorsAmiin.turquoiseDk,
                                  )),
                                  const SizedBox(height: 6),
                                  Text(_note!.agentContext!, style: TextStyle(
                                    fontFamily: FontFamily.sans,
                                    fontSize: 13,
                                    color: ColorsAmiin.turquoiseDk,
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
                              child: Text('Supprimer cette note', style: TextStyle(color: ColorsAmiin.muted)),
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

  static const String _checkSvg = '''
    <svg width="22" height="22" viewBox="0 0 22 22" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path d="M4 12l5 5 9-10" stroke="#B85530" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>
  ''';
  static const String _editSvg = '''
    <svg width="20" height="20" viewBox="0 0 20 20" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path d="M14 2l4 4-10 10H4v-4L14 2z" stroke="#B85530" stroke-width="1.6" stroke-linejoin="round"/>
    </svg>
  ''';
}

