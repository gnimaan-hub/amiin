// ─── ChatScreen ──────────────────────────────────────────────────────────────
// Couche présentation uniquement : rendu des bulles, saisie, STT/TTS, scroll.
// Toute l'orchestration agentique vit dans ChatController.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/amiin_logo.dart';
import '../../services/chat_controller.dart';
import '../../services/connectivity_service.dart';
import '../../models/chat_message.dart';
import '../../widgets/toast.dart';
import '../../widgets/chat_note_card.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  ChatController? _chat;
  StreamSubscription<ChatNotice>? _noticeSub;

  // Speech-to-text
  late stt.SpeechToText _speech;
  bool _isListening = false;
  bool _speechAvailable = false;

  /// true si le texte du champ provient de la dictée vocale →
  /// la réponse sera lue à voix haute. Jamais de TTS pour une question tapée.
  bool _dictated = false;

  // Text-to-speech
  late FlutterTts _flutterTts;
  bool _isSpeaking = false;
  String? _speakingMsgId;

  // Animation points + pulsation micro
  late AnimationController _dotsController;
  late Animation<double> _dotsAnimation;

  // Questions proposées quand la conversation est vide
  static const List<String> _starterQuestions = [
    'Comment renouveler mon passeport ?',
    'Quels documents pour un acte de naissance ?',
    'Rappelle-moi mes prochains rendez-vous',
    'Crée une note avec ma liste de documents',
  ];

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _initTts();

    _dotsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _dotsAnimation = Tween<double>(begin: 0, end: 1).animate(_dotsController);

    _chat = context.read<ChatController>();
    _chat!.addListener(_onChatChanged);
    _noticeSub = _chat!.notices.listen((n) {
      if (mounted) AmiinToast.show(context, n.message, success: n.success);
    });

    // L'accueil peut demander le démarrage immédiat de l'écoute vocale
    chatListenRequest.addListener(_onListenRequest);

    // Scroll au dernier message après le premier rendu complet
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    });
  }

  @override
  void dispose() {
    chatListenRequest.removeListener(_onListenRequest);
    _chat?.removeListener(_onChatChanged);
    _noticeSub?.cancel();
    _speech.stop();
    _flutterTts.stop();
    _scrollController.dispose();
    _controller.dispose();
    _dotsController.dispose();
    super.dispose();
  }

  // ── Scroll intelligent ───────────────────────────────────────────────────
  // On ne suit le bas que si l'utilisateur y est déjà : il peut remonter
  // lire le début de la réponse sans être "aspiré" à chaque token.

  bool get _nearBottom {
    if (!_scrollController.hasClients) return true;
    final pos = _scrollController.position;
    return pos.maxScrollExtent - pos.pixels < 120;
  }

  void _onChatChanged() {
    if (!mounted) return;
    final follow = _nearBottom;
    setState(() {});
    if (follow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    }
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      if (animate) {
        _scrollController.animateTo(max,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut);
      } else {
        _scrollController.jumpTo(max);
      }
    });
  }

  // ── Demande d'écoute depuis l'accueil ────────────────────────────────────

  void _onListenRequest() {
    // Laisser la navigation se terminer avant d'ouvrir le micro
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted && !_isListening && !(_chat?.isBusy ?? true)) {
        _toggleRecording();
      }
    });
  }

  // ── Speech-to-text ───────────────────────────────────────────────────────

  void _initSpeech() async {
    _speech = stt.SpeechToText();
    _speechAvailable = await _speech.initialize(
      onStatus: (status) {
        // Quand le moteur s'arrête (silence détecté ou timeout), on met à jour
        // l'UI mais on N'envoie PAS automatiquement : c'est l'utilisateur
        // qui décide d'envoyer via le bouton.
        if ((status == 'done' || status == 'notListening') && mounted) {
          setState(() => _isListening = false);
        }
      },
      onError: (error) => debugPrint('STT error: $error'),
    );
    if (mounted) setState(() {});
  }

  /// Tap = bascule enregistrement. L'envoi reste manuel via le bouton send.
  Future<void> _toggleRecording() async {
    HapticFeedback.lightImpact();
    // Couper le TTS si en cours — micro et haut-parleur ne coexistent pas
    if (_isSpeaking) await _stopSpeaking();

    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }

    if (!_speechAvailable) {
      if (mounted) {
        AmiinToast.show(context, 'Reconnaissance vocale non disponible.',
            success: false);
      }
      return;
    }

    final hasPermission = await _speech.hasPermission;
    if (!hasPermission) {
      final ok = await _speech.initialize();
      if (!ok) {
        if (mounted) {
          AmiinToast.show(context, 'Permission microphone refusée.',
              success: false);
        }
        return;
      }
    }

    setState(() => _isListening = true);
    _speech.listen(
      onResult: _onSpeechResult,
      listenFor: const Duration(seconds: 120),
      // Silence toléré long : 10s pour laisser le temps de réfléchir entre
      // les phrases sans déclencher un arrêt prématuré.
      pauseFor: const Duration(seconds: 10),
      localeId: 'fr_FR',
    );
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    _dictated = true;
    setState(() => _controller.text = result.recognizedWords);
  }

  // ── Text-to-speech ───────────────────────────────────────────────────────

  void _initTts() {
    _flutterTts = FlutterTts();
    _flutterTts.setLanguage('fr-FR');
    _flutterTts.setSpeechRate(0.75);
    _flutterTts.setPitch(1.0);
    _flutterTts.setCompletionHandler(() {
      if (mounted) {
        setState(() {
          _isSpeaking = false;
          _speakingMsgId = null;
        });
      }
    });
  }

  String _cleanTextForTts(String text) {
    text = text.replaceAll(RegExp(r'\[([^\]]+)\]\([^\)]+\)'), r'$1');
    text = text.replaceAll(RegExp(r'!\[[^\]]*\]\([^\)]+\)'), '');
    text = text.replaceAll(RegExp(r'^#{1,6}\s+', multiLine: true), '');
    text = text.replaceAll(RegExp(r'^[\*\-+]\s+', multiLine: true), '');
    text = text.replaceAll(RegExp(r'^\d+\.\s+', multiLine: true), '');
    text = text.replaceAll(RegExp(r'\*'), '');
    text = text.replaceAll(RegExp(r'_'), '');
    text = text.replaceAll(RegExp(r'[\u{1F600}-\u{1F9FF}]', unicode: true), '');
    text = text.replaceAll(RegExp(r'[\u{2600}-\u{27BF}]', unicode: true), '');
    text = text.replaceAll(RegExp(r'[→←↑↓✔✓✗✘✅❌]'), '');
    text = text.replaceAll(RegExp(r'\n+'), '. ');
    text = text.replaceAll(RegExp(r'\s+'), ' ');
    return text.trim();
  }

  Future<void> _speak(String text, {String? msgId}) async {
    if (_isSpeaking) await _flutterTts.stop();
    final cleaned = _cleanTextForTts(text);
    if (cleaned.isEmpty) return;
    if (mounted) {
      setState(() {
        _isSpeaking = true;
        _speakingMsgId = msgId;
      });
    }
    await _flutterTts.speak(cleaned);
  }

  Future<void> _stopSpeaking() async {
    await _flutterTts.stop();
    if (mounted) {
      setState(() {
        _isSpeaking = false;
        _speakingMsgId = null;
      });
    }
  }

  // ── Envoi ────────────────────────────────────────────────────────────────

  Future<void> _sendMessage([String? presetText]) async {
    final chat = _chat!;
    final text = (presetText ?? _controller.text).trim();
    if (text.isEmpty || chat.isBusy) return;

    // Hors-ligne : garder le texte saisi et prévenir clairement
    if (!connectivityService.isOnline) {
      AmiinToast.show(context, 'Vous êtes hors ligne — message non envoyé.',
          success: false);
      return;
    }

    HapticFeedback.lightImpact();
    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
    }
    if (_isSpeaking) await _stopSpeaking();

    final wasVoice = _dictated;
    _dictated = false;
    _controller.clear();
    _scrollToBottom();

    final reply = await chat.sendMessage(text);

    // Lecture vocale uniquement si la question a été dictée
    if (reply != null && wasVoice && mounted) {
      final msgs = chat.messages;
      final msgId = msgs.isNotEmpty ? msgs.last.id : null;
      await _speak(reply, msgId: msgId);
    }
  }

  void _cancelRequest() {
    HapticFeedback.lightImpact();
    _chat?.cancel();
  }

  void _confirmNewConversation() {
    final chat = _chat!;
    if (chat.messages.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Nouvelle conversation'),
        content: const Text(
            'Effacer la conversation actuelle et repartir de zéro ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              _stopSpeaking();
              chat.clearConversation();
            },
            style: TextButton.styleFrom(foregroundColor: ColorsAmiin.terra),
            child: const Text('Effacer'),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).padding;
    final chat = context.watch<ChatController>();

    return Scaffold(
      backgroundColor: ColorsAmiin.ecru,
      body: Column(
        children: [
          _buildHeader(insets, chat),

          // Liste des messages
          Expanded(
            child: chat.messages.isEmpty
                ? _buildEmptyState(chat)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(Spacing.lg),
                    itemCount:
                        chat.messages.length + (chat.isLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      // Bulle "Amiin réfléchit" à la fin
                      if (chat.isLoading && index == chat.messages.length) {
                        return const Padding(
                          padding: EdgeInsets.only(bottom: Spacing.sm),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _AvatarA(),
                              SizedBox(width: Spacing.sm),
                              _ThinkingBubble(),
                            ],
                          ),
                        );
                      }
                      return _buildMessageItem(chat, index);
                    },
                  ),
          ),

          _buildInputBar(insets, chat),
        ],
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────

  Widget _buildHeader(EdgeInsets insets, ChatController chat) {
    return Container(
      color: ColorsAmiin.ink,
      padding: EdgeInsets.only(
          top: insets.top + 8, bottom: 12, left: Spacing.xl, right: Spacing.md),
      child: Row(
        children: [
          const AmiinLogo(size: 32, variant: AmiinLogoVariant.dark),
          const SizedBox(width: Spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Amiin',
                    style: TextStyle(
                        fontFamily: FontFamily.serif,
                        fontSize: 16,
                        color: ColorsAmiin.onDark)),
                _buildHeaderStatus(chat),
              ],
            ),
          ),
          IconButton(
            onPressed: chat.messages.isEmpty ? null : _confirmNewConversation,
            tooltip: 'Nouvelle conversation',
            icon: Icon(
              Icons.add_comment_outlined,
              size: 20,
              color: chat.messages.isEmpty
                  ? ColorsAmiin.onDark.withValues(alpha: 0.25)
                  : ColorsAmiin.onDark.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderStatus(ChatController chat) {
    const green = Color(0xFF5A9A5A);
    return ListenableBuilder(
      listenable: connectivityService,
      builder: (context, _) {
        if (!connectivityService.isOnline) {
          return Text('Hors ligne',
              style: TextStyle(
                  fontFamily: FontFamily.sans,
                  fontSize: 11,
                  color: const Color(0xFFE57373)));
        }
        if (chat.isBusy) {
          return Row(
            children: [
              Text(
                chat.isLoading
                    ? (chat.streamStatus.isNotEmpty
                        ? chat.streamStatus
                        : 'Recherche…')
                    : 'Rédige…',
                style: TextStyle(
                    fontFamily: FontFamily.sans, fontSize: 11, color: green),
              ),
              const SizedBox(width: 4),
              AnimatedBuilder(
                animation: _dotsAnimation,
                builder: (context, _) {
                  final count = ((_dotsAnimation.value * 3).floor() % 3) + 1;
                  return Text('.' * count,
                      style: TextStyle(
                          fontFamily: FontFamily.sans,
                          fontSize: 14,
                          color: green));
                },
              ),
            ],
          );
        }
        return Text(
          _isListening
              ? 'Écoute…'
              : _isSpeaking
                  ? 'Parle…'
                  : 'En ligne',
          style: TextStyle(
              fontFamily: FontFamily.sans,
              fontSize: 11,
              color: _isListening ? ColorsAmiin.terra : green),
        );
      },
    );
  }

  // ── Message ───────────────────────────────────────────────────────────────

  Widget _buildMessageItem(ChatController chat, int index) {
    final msg = chat.messages[index];
    final isUser = msg.role == 'user';
    final showDateSep = index == 0 ||
        !_isSameDay(msg.timestamp, chat.messages[index - 1].timestamp);

    return Column(
      children: [
        if (showDateSep)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.md),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.md, vertical: 4),
                decoration: BoxDecoration(
                  color: ColorsAmiin.border,
                  borderRadius: BorderRadius.circular(RadiusAmiin.sm),
                ),
                child: Text(
                  DateFormat('EEEE d MMMM yyyy', 'fr').format(msg.timestamp),
                  style: TextStyle(
                      fontFamily: FontFamily.sansMedium,
                      fontSize: 11,
                      color: ColorsAmiin.muted),
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: Spacing.sm),
          child: Row(
            mainAxisAlignment:
                isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isUser) const _AvatarA(),
              const SizedBox(width: Spacing.sm),
              Flexible(
                child: GestureDetector(
                  onLongPress: () => _showMessageMenu(context, msg),
                  child: Container(
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.78),
                    decoration: BoxDecoration(
                      color: isUser ? ColorsAmiin.terra : ColorsAmiin.white,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(RadiusAmiin.lg),
                        topRight: const Radius.circular(RadiusAmiin.lg),
                        bottomLeft: isUser
                            ? const Radius.circular(RadiusAmiin.lg)
                            : const Radius.circular(4),
                        bottomRight: isUser
                            ? const Radius.circular(4)
                            : const Radius.circular(RadiusAmiin.lg),
                      ),
                      border: isUser
                          ? null
                          : Border.all(color: ColorsAmiin.border),
                    ),
                    padding: const EdgeInsets.all(Spacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MarkdownBody(
                          data: msg.content,
                          styleSheet: MarkdownStyleSheet(
                            p: TextStyle(
                                fontFamily: FontFamily.sans,
                                fontSize: 14,
                                color: isUser
                                    ? ColorsAmiin.white
                                    : ColorsAmiin.ink,
                                height: 1.5),
                          ),
                          selectable: true,
                        ),
                        // Chips d'actions avec libellés conviviaux
                        if (msg.actions != null)
                          ...msg.actions!.map(
                            (action) => Padding(
                              padding: const EdgeInsets.only(top: Spacing.sm),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: Spacing.sm, vertical: 4),
                                decoration: BoxDecoration(
                                    color: ColorsAmiin.terraLt,
                                    borderRadius: BorderRadius.circular(
                                        RadiusAmiin.sm)),
                                child: Text(
                                    ChatController.actionLabel(action.name),
                                    style: TextStyle(
                                        fontFamily: FontFamily.sansBold,
                                        fontSize: 12,
                                        color: ColorsAmiin.terraDk)),
                              ),
                            ),
                          ),
                        // Carte note créée/modifiée par Amiin
                        if (!isUser && chat.noteResults.containsKey(msg.id))
                          ChatNoteCard(
                            noteId: chat.noteResults[msg.id]!.id,
                            noteTitle: chat.noteResults[msg.id]!.title,
                            noteContent: chat.noteResults[msg.id]!.content,
                            isUpdate: msg.actions
                                    ?.any((a) => a.name == 'update_note') ??
                                false,
                          ),
                        // Carte événement créé/modifié par Amiin
                        if (!isUser && chat.eventResults.containsKey(msg.id))
                          ChatEventCard(
                            eventId: chat.eventResults[msg.id]!.id,
                            eventTitle: chat.eventResults[msg.id]!.title,
                            eventDate: chat.eventResults[msg.id]!.date,
                            isUpdate: msg.actions
                                    ?.any((a) => a.name == 'update_event') ??
                                false,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Heure + bouton écoute (messages d'Amiin)
        Padding(
          padding: EdgeInsets.only(
            left: isUser ? 0 : 36,
            right: isUser ? 36 : 0,
            bottom: Spacing.md,
          ),
          child: Row(
            mainAxisAlignment:
                isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              Text(
                DateFormat('HH:mm').format(msg.timestamp),
                style: TextStyle(
                    fontFamily: FontFamily.sans,
                    fontSize: 10,
                    color: ColorsAmiin.muted),
              ),
              if (!isUser && msg.content.isNotEmpty) ...[
                const SizedBox(width: Spacing.sm),
                InkWell(
                  onTap: () => _speakingMsgId == msg.id
                      ? _stopSpeaking()
                      : _speak(msg.content, msgId: msg.id),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Icon(
                      _speakingMsgId == msg.id
                          ? Icons.stop_circle_outlined
                          : Icons.volume_up_outlined,
                      size: 16,
                      color: _speakingMsgId == msg.id
                          ? ColorsAmiin.terra
                          : ColorsAmiin.muted,
                      semanticLabel: _speakingMsgId == msg.id
                          ? 'Arrêter la lecture'
                          : 'Écouter la réponse',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        // Métriques d'usage (tokens Claude / Jina / outils)
        if (!isUser && chat.messageUsage.containsKey(msg.id))
          _buildUsageBar(chat.messageUsage[msg.id]!),
        // Confirmation de suppression demandée par Amiin
        if (!isUser &&
            chat.pendingDeletionMsgId == msg.id &&
            chat.pendingDeletions.isNotEmpty)
          ChatDeleteConfirm(
            descriptions:
                chat.pendingDeletions.map((p) => p.description).toList(),
            onConfirm: chat.confirmPendingDeletions,
            onDismiss: chat.dismissPendingDeletions,
          ),
        // Suggestion proactive de créer une note
        if (!isUser &&
            chat.noteSuggestionMsgId == msg.id &&
            chat.noteSuggestionText != null)
          ChatNoteSuggestion(
            suggestionText: chat.noteSuggestionText!,
            onConfirm: () => chat.createNoteFromSuggestion(msg.id),
            onDismiss: chat.dismissNoteSuggestion,
          ),
      ],
    );
  }

  // ── Barre métriques d'usage ───────────────────────────────────────────────

  Widget _buildUsageBar(Map<String, dynamic> usage) {
    final claudeIn  = usage['claude_input']      as int? ?? 0;
    final claudeOut = usage['claude_output']     as int? ?? 0;
    final cacheRead = usage['claude_cache_read'] as int? ?? 0;
    final jinaTokens = usage['jina_tokens']      as int? ?? 0;
    final tools = (usage['tools'] as List?)?.cast<String>() ?? const <String>[];

    final parts = <String>[
      'Claude ▲$claudeIn ▼$claudeOut',
      if (cacheRead > 0) '💾 $cacheRead',
      if (jinaTokens > 0) '· Jina $jinaTokens',
      if (tools.isNotEmpty)
        '· ${tools.map(ChatController.actionLabel).join(', ')}',
    ];

    return Padding(
      padding: const EdgeInsets.only(left: 44, bottom: 6),
      child: Text(
        parts.join(' '),
        style: TextStyle(
          fontFamily: FontFamily.sans,
          fontSize: 9,
          color: ColorsAmiin.muted,
        ),
      ),
    );
  }

  // ── Barre de saisie ───────────────────────────────────────────────────────

  Widget _buildInputBar(EdgeInsets insets, ChatController chat) {
    return Container(
      padding: EdgeInsets.only(
          left: Spacing.lg,
          right: Spacing.lg,
          top: Spacing.sm,
          bottom: insets.bottom + 8),
      decoration: const BoxDecoration(
          color: ColorsAmiin.white,
          border: Border(top: BorderSide(color: ColorsAmiin.border))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Champ texte
          Expanded(
            child: TextField(
              controller: _controller,
              maxLines: null,
              maxLength: 1000,
              onChanged: (_) {
                // Saisie manuelle → pas de lecture vocale automatique
                _dictated = false;
              },
              onSubmitted: (_) => _sendMessage(),
              decoration: InputDecoration(
                hintText: _isListening
                    ? 'En écoute… tapez à nouveau le micro pour arrêter'
                    : 'Écrivez votre question…',
                hintStyle: TextStyle(
                    fontFamily: FontFamily.sans,
                    fontSize: 14,
                    color: ColorsAmiin.muted),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(RadiusAmiin.xl),
                    borderSide: BorderSide.none),
                filled: true,
                fillColor: _isListening
                    ? ColorsAmiin.terraLt.withValues(alpha: 0.3)
                    : ColorsAmiin.ecru,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: Spacing.md, vertical: Spacing.sm),
              ),
              // Compteur visible uniquement à l'approche de la limite —
              // plus de "mur invisible" à 1000 caractères.
              buildCounter: (context,
                  {required currentLength, required isFocused, maxLength}) {
                if (currentLength < 900 || maxLength == null) return null;
                return Text(
                  '$currentLength / $maxLength',
                  style: TextStyle(
                    fontFamily: FontFamily.sans,
                    fontSize: 10,
                    color: currentLength >= maxLength
                        ? ColorsAmiin.terra
                        : ColorsAmiin.muted,
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: Spacing.sm),

          // Bouton microphone (tap pour basculer)
          if (!chat.isBusy)
            Semantics(
              button: true,
              label: _isListening
                  ? 'Arrêter la dictée vocale'
                  : 'Dicter une question',
              child: Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: _toggleRecording,
                  customBorder: const CircleBorder(),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _isListening
                          ? ColorsAmiin.terra
                          : ColorsAmiin.terra.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: _isListening
                          ? Border.all(color: ColorsAmiin.terraDk, width: 2)
                          : null,
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (_isListening)
                          AnimatedBuilder(
                            animation: _dotsAnimation,
                            builder: (_, __) => Container(
                              width: 44 + 10 * _dotsAnimation.value,
                              height: 44 + 10 * _dotsAnimation.value,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color:
                                    ColorsAmiin.terra.withValues(alpha: 0.2),
                              ),
                            ),
                          ),
                        Icon(
                          _isListening ? Icons.mic : Icons.mic_none,
                          color: _isListening
                              ? ColorsAmiin.white
                              : ColorsAmiin.terra,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

          const SizedBox(width: Spacing.sm),

          // Bouton stop (pendant requête/stream) ou send
          if (chat.isBusy)
            Semantics(
              button: true,
              label: 'Arrêter la réponse',
              child: Material(
                color: ColorsAmiin.muted,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: _cancelRequest,
                  customBorder: const CircleBorder(),
                  child: const SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(Icons.stop, color: ColorsAmiin.white),
                  ),
                ),
              ),
            )
          else
            Semantics(
              button: true,
              label: 'Envoyer le message',
              child: Material(
                color: ColorsAmiin.terra,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: _sendMessage,
                  customBorder: const CircleBorder(),
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Center(
                        child:
                            SvgPicture.string(_sendSvg, width: 20, height: 20)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Menu contextuel d'un message ──────────────────────────────────────────

  void _showMessageMenu(BuildContext context, ChatMessage msg) {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: ColorsAmiin.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: ColorsAmiin.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading:
                  const Icon(Icons.copy_outlined, color: ColorsAmiin.terra),
              title: Text('Copier',
                  style: TextStyle(fontFamily: FontFamily.sansMedium)),
              onTap: () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(text: msg.content));
                AmiinToast.show(context, 'Message copié');
              },
            ),
            if (msg.role != 'user')
              ListTile(
                leading: const Icon(Icons.volume_up_outlined,
                    color: ColorsAmiin.terra),
                title: Text('Écouter',
                    style: TextStyle(fontFamily: FontFamily.sansMedium)),
                onTap: () {
                  Navigator.pop(context);
                  _speak(msg.content, msgId: msg.id);
                },
              ),
            if (msg.role == 'user')
              ListTile(
                leading: const Icon(Icons.refresh_outlined,
                    color: ColorsAmiin.terra),
                title: Text('Retenter',
                    style: TextStyle(fontFamily: FontFamily.sansMedium)),
                onTap: () {
                  Navigator.pop(context);
                  _sendMessage(msg.content);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── État vide avec questions de démarrage ─────────────────────────────────

  Widget _buildEmptyState(ChatController chat) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const AmiinLogo(size: 56, variant: AmiinLogoVariant.dark),
            const SizedBox(height: Spacing.md),
            Text('Bonjour — je suis Amiin',
                style: TextStyle(
                    fontFamily: FontFamily.serif,
                    fontSize: 20,
                    color: ColorsAmiin.ink)),
            const SizedBox(height: Spacing.sm),
            Text(
              'Posez-moi une question sur vos démarches administratives,\nvotre agenda ou les services publics de Djibouti.',
              style: TextStyle(
                  fontFamily: FontFamily.sansLight,
                  fontSize: 14,
                  color: ColorsAmiin.muted,
                  height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.xl),
            // Questions types : enseignent le périmètre d'Amiin
            ..._starterQuestions.map(
              (q) => Padding(
                padding: const EdgeInsets.only(bottom: Spacing.sm),
                child: Material(
                  color: ColorsAmiin.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(RadiusAmiin.xl),
                    side: const BorderSide(color: ColorsAmiin.border),
                  ),
                  child: InkWell(
                    onTap: () => _sendMessage(q),
                    customBorder: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(RadiusAmiin.xl),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: Spacing.lg, vertical: Spacing.sm + 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.chat_bubble_outline,
                              size: 14, color: ColorsAmiin.terra),
                          const SizedBox(width: Spacing.sm),
                          Flexible(
                            child: Text(
                              q,
                              style: TextStyle(
                                  fontFamily: FontFamily.sans,
                                  fontSize: 13,
                                  color: ColorsAmiin.ink),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const String _sendSvg = '''
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
      <path d="M22 2L11 13" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
      <path d="M22 2L15 22L11 13L2 9L22 2Z" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>
    </svg>
  ''';
}

// ── Avatar "A" d'Amiin ──────────────────────────────────────────────────────
class _AvatarA extends StatelessWidget {
  const _AvatarA();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: const BoxDecoration(
        color: ColorsAmiin.terra,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          'A',
          style: TextStyle(
            fontFamily: FontFamily.serif,
            fontSize: 13,
            color: ColorsAmiin.white,
          ),
        ),
      ),
    );
  }
}

// ── Bulle de réflexion avec points flottants ────────────────────────────────
class _ThinkingBubble extends StatefulWidget {
  const _ThinkingBubble();

  @override
  State<_ThinkingBubble> createState() => _ThinkingBubbleState();
}

class _ThinkingBubbleState extends State<_ThinkingBubble>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  late final List<Animation<double>> _offsets;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      3,
      (_) => AnimationController(
        duration: const Duration(milliseconds: 500),
        vsync: this,
      ),
    );
    _offsets = _controllers
        .map(
          (c) => Tween(begin: 0.0, end: -6.0).animate(
            CurvedAnimation(parent: c, curve: Curves.easeInOut),
          ),
        )
        .toList();

    for (int i = 0; i < 3; i++) {
      Future.delayed(Duration(milliseconds: i * 160), () {
        if (mounted) _controllers[i].repeat(reverse: true);
      });
    }
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: ColorsAmiin.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(RadiusAmiin.lg),
          topRight: Radius.circular(RadiusAmiin.lg),
          bottomLeft: Radius.circular(4),
          bottomRight: Radius.circular(RadiusAmiin.lg),
        ),
        border: Border.all(color: ColorsAmiin.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          return AnimatedBuilder(
            animation: _offsets[i],
            builder: (_, __) => Transform.translate(
              offset: Offset(0, _offsets[i].value),
              child: Container(
                width: 7,
                height: 7,
                margin: EdgeInsets.only(right: i < 2 ? 5 : 0),
                decoration: BoxDecoration(
                  color: ColorsAmiin.terra.withValues(alpha: 0.6),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
