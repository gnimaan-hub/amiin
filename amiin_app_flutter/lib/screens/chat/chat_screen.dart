// ─── ChatScreen ──────────────────────────────────────────────────────────────
// Couche présentation uniquement : rendu des bulles, saisie, STT/TTS, scroll.
// Toute l'orchestration agentique vit dans ChatController.

import 'dart:async';

import 'package:flutter/material.dart';
import '../../widgets/amiin_svg_icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:go_router/go_router.dart';

import '../../services/cloud_tts_service.dart';
import '../../services/settings_service.dart';

import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../theme/themes.dart';
import '../../widgets/amiin_logo.dart';
import '../../widgets/horizon_line.dart';
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

  /// La liste reste invisible tant que le scroll initial n'est pas posé en
  /// bas — évite le flash « haut de conversation → saut vers le bas ».
  bool _listReady = false;

  ChatController? _chat;
  StreamSubscription<ChatNotice>? _noticeSub;

  // Speech-to-text
  late stt.SpeechToText _speech;
  bool _isListening = false;
  bool _speechAvailable = false;

  bool _dictated = false;

  // Text-to-speech
  late FlutterTts _flutterTts;
  bool _isSpeaking = false;
  String? _speakingMsgId;

  /// Session TTS « live » : la voix démarre pendant le streaming SSE,
  /// alimentée phrase par phrase depuis _onChatChanged.
  bool _liveTtsActive = false;

  // Animation dots
  late AnimationController _dotsController;
  late Animation<double> _dotsAnimation;

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

    chatListenRequest.addListener(_onListenRequest);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
        // Le rendu markdown peut encore étendre la liste après ce frame :
        // on re-cale une fois, puis on révèle la liste déjà en bas.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(
              _scrollController.position.maxScrollExtent,
            );
          }
          setState(() => _listReady = true);
        });
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

  bool get _nearBottom {
    if (!_scrollController.hasClients) return true;
    final pos = _scrollController.position;
    return pos.maxScrollExtent - pos.pixels < 120;
  }

  void _onChatChanged() {
    if (!mounted) return;

    // Voix en direct : chaque notification du stream pousse le texte
    // accumulé — le service n'en synthétise que les nouvelles phrases.
    if (_liveTtsActive) {
      final msgs = _chat?.messages ?? const [];
      if (msgs.isNotEmpty && msgs.last.role == 'agent') {
        cloudTtsService.setSessionMsgId(msgs.last.id);
        cloudTtsService.feedText(msgs.last.content);
      }
    }

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
        _scrollController.animateTo(
          max,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(max);
      }
    });
  }

  void _onListenRequest() {
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted && !_isListening && !(_chat?.isBusy ?? true)) {
        _toggleRecording();
      }
    });
  }

  void _initSpeech() async {
    _speech = stt.SpeechToText();
    try {
      _speechAvailable = await _speech.initialize(
        onStatus: (status) {
          if ((status == 'done' || status == 'notListening') && mounted) {
            setState(() => _isListening = false);
          }
        },
        onError: (error) => debugPrint('STT error: $error'),
      );
    } catch (e) {
      // Certains téléphones n'ont pas de service de reconnaissance vocale
      // (ou Google app désactivée) : on dégrade sans crasher, le micro
      // affichera un message explicatif au tap.
      _speechAvailable = false;
      debugPrint('Reconnaissance vocale indisponible : $e');
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleRecording() async {
    HapticFeedback.lightImpact();
    if (_isSpeaking) await _stopSpeaking();

    if (_isListening) {
      await _speech.stop();
      setState(() => _isListening = false);
      return;
    }

    if (!_speechAvailable) {
      if (mounted)
        AmiinToast.show(
          context,
          'Reconnaissance vocale non disponible.',
          success: false,
        );
      return;
    }

    final hasPermission = await _speech.hasPermission;
    if (!hasPermission) {
      final ok = await _speech.initialize();
      if (!ok) {
        if (mounted)
          AmiinToast.show(
            context,
            'Permission microphone refusée.',
            success: false,
          );
        return;
      }
    }

    setState(() => _isListening = true);
    _speech.listen(
      onResult: _onSpeechResult,
      listenFor: const Duration(seconds: 120),
      pauseFor: const Duration(seconds: 10),
      localeId: 'fr_FR',
    );
  }

  void _onSpeechResult(SpeechRecognitionResult result) {
    _dictated = true;
    setState(() => _controller.text = result.recognizedWords);
  }

  void _initTts() {
    _flutterTts = FlutterTts();
    _flutterTts.setLanguage('fr-FR');
    _flutterTts.setSpeechRate(0.75);
    _flutterTts.setPitch(1.0);
    _flutterTts.setCompletionHandler(() {
      if (mounted)
        setState(() {
          _isSpeaking = false;
          _speakingMsgId = null;
        });
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
    if (_isSpeaking) await _stopSpeaking();
    final cleaned = _cleanTextForTts(text);
    if (cleaned.isEmpty) return;
    if (mounted)
      setState(() {
        _isSpeaking = true;
        _speakingMsgId = msgId;
      });

    if (settingsService.useCloudTts) {
      // Moteur cloud Edge TTS — haute qualité, indépendant des voix système.
      // En cas d'erreur réseau, bascule automatiquement sur flutter_tts.
      try {
        await cloudTtsService.speak(cleaned, msgId: msgId);
      } catch (_) {
        await _flutterTts.speak(cleaned);
      }
      if (mounted)
        setState(() {
          _isSpeaking = false;
          _speakingMsgId = null;
        });
    } else {
      // Moteur local flutter_tts — fin de lecture gérée par setCompletionHandler.
      await _flutterTts.speak(cleaned);
    }
  }

  Future<void> _stopSpeaking() async {
    _liveTtsActive = false;
    if (settingsService.useCloudTts) {
      await cloudTtsService.stop();
    } else {
      await _flutterTts.stop();
    }
    if (mounted)
      setState(() {
        _isSpeaking = false;
        _speakingMsgId = null;
      });
  }

  Future<void> _sendMessage([String? presetText]) async {
    final chat = _chat!;
    final text = (presetText ?? _controller.text).trim();
    if (text.isEmpty || chat.isBusy) return;

    if (!connectivityService.isOnline) {
      AmiinToast.show(
        context,
        'Vous êtes hors ligne — message non envoyé.',
        success: false,
      );
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

    // 'none'  → jamais de lecture auto
    // 'tts'   → lecture auto sur toute réponse (texte ou voix)
    // 'voice' → lecture seulement si le message a été dicté
    final mode = settingsService.defaultVoiceMode;
    final wantAutoRead = mode == 'tts' || (mode == 'voice' && wasVoice);

    // Voix en direct (cloud uniquement) : la session démarre AVANT la
    // réponse — la 1re phrase sera parlée pendant que le reste streame.
    final liveTts = wantAutoRead && settingsService.useCloudTts;
    if (liveTts) {
      _liveTtsActive = true;
      cloudTtsService.beginSession(cleaner: _cleanTextForTts);
      setState(() => _isSpeaking = true);
    }

    final reply = await chat.sendMessage(text);

    if (liveTts) {
      _liveTtsActive = false;
      final produced = await cloudTtsService.endSession(reply ?? '');
      if (mounted) {
        setState(() {
          _isSpeaking = false;
          _speakingMsgId = null;
        });
      }
      // Rien n'a pu être synthétisé (réseau TTS en panne pendant tout le
      // stream) → repli sur le moteur local avec le texte complet.
      if (!produced && reply != null && mounted) {
        await _flutterTts.speak(_cleanTextForTts(reply));
      }
    } else if (reply != null && mounted && wantAutoRead) {
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
          'Effacer la conversation actuelle et repartir de zéro ?',
        ),
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
            style: TextButton.styleFrom(foregroundColor: context.ac.alertColor),
            child: const Text('Effacer'),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).padding;
    final chat = context.watch<ChatController>();
    final ac = context.ac;

    return Scaffold(
      backgroundColor: ac.background,
      body: Column(
        children: [
          _buildHeader(insets, chat, ac),
          Expanded(
            child: chat.messages.isEmpty
                ? _buildEmptyState(chat, ac)
                : Opacity(
                    opacity: _listReady ? 1.0 : 0.0,
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(
                        Spacing.lg,
                        Spacing.lg,
                        Spacing.lg,
                        Spacing.sm,
                      ),
                      itemCount:
                          chat.messages.length + (chat.isLoading ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (chat.isLoading && index == chat.messages.length) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: Spacing.sm),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                _AvatarA(color: ac.secretariatAccent),
                                const SizedBox(width: Spacing.sm),
                                _ThinkingBubble(color: ac.secretariatAccent),
                              ],
                            ),
                          );
                        }
                        return _buildMessageItem(chat, index, ac);
                      },
                    ),
                  ),
          ),
          _buildInputBar(insets, chat, ac),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader(
    EdgeInsets insets,
    ChatController chat,
    AmiinThemeColors ac,
  ) {
    return Container(
      color: ac.headerGradientEnd,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(height: insets.top + 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(Spacing.xl, 0, Spacing.md, 12),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => context.go('/home'),
                  child: const AmiinLogo(
                    size: 30,
                    variant: AmiinLogoVariant.turquoise,
                  ),
                ),
                const SizedBox(width: Spacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Amiin',
                        style: TextStyles.cardTitle(context).copyWith(fontSize: 15, color: ac.onHeader, letterSpacing: 0.3, fontFamily: FontFamily.geoBold),
                      ),
                      _buildHeaderStatus(chat, ac),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: chat.messages.isEmpty
                      ? null
                      : _confirmNewConversation,
                  tooltip: 'Nouvelle conversation',
                  icon: Icon(
                    Icons.add_comment_outlined,
                    size: 20,
                    color: chat.messages.isEmpty
                        ? ac.onHeader.withValues(alpha: 0.2)
                        : ac.onHeader.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
          // Ligne d'horizon — chargement ou état stable
          HorizonLine(color: ac.secretariatAccent, animating: chat.isBusy),
        ],
      ),
    );
  }

  Widget _buildHeaderStatus(ChatController chat, AmiinThemeColors ac) {
    return ListenableBuilder(
      listenable: connectivityService,
      builder: (context, _) {
        if (!connectivityService.isOnline) {
          return Text(
            'Hors ligne',
            style: TextStyles.body(context).copyWith(fontSize: 11, color: context.ac.alertColor),
          );
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
                style: TextStyles.body(context).copyWith(fontSize: 11, color: ac.secretariatAccent),
              ),
              const SizedBox(width: 4),
              AnimatedBuilder(
                animation: _dotsAnimation,
                builder: (context, _) {
                  final count = ((_dotsAnimation.value * 3).floor() % 3) + 1;
                  return Text(
                    '.' * count,
                    style: TextStyles.body(context).copyWith(color: ac.secretariatAccent),
                  );
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
          style: TextStyles.body(context).copyWith(fontSize: 11, color: _isListening
                ? context.ac.secretariatAccentMid
                : ac.onHeader.withValues(alpha: 0.4)),
        );
      },
    );
  }

  // ── Message ────────────────────────────────────────────────────────────────

  Widget _buildMessageItem(
    ChatController chat,
    int index,
    AmiinThemeColors ac,
  ) {
    final msg = chat.messages[index];
    final isUser = msg.role == 'user';
    final showDateSep =
        index == 0 ||
        !_isSameDay(msg.timestamp, chat.messages[index - 1].timestamp);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showDateSep)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.md),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md,
                  vertical: Spacing.xs,
                ),
                decoration: BoxDecoration(
                  color: ac.surface2,
                  borderRadius: BorderRadius.circular(RadiusAmiin.sm),
                ),
                child: Text(
                  DateFormat('EEEE d MMMM', 'fr').format(msg.timestamp),
                  style: TextStyles.sectionLabel(context).copyWith(fontSize: 11, fontFamily: FontFamily.geoMedium),
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(bottom: Spacing.xs),
          child: Row(
            mainAxisAlignment: isUser
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isUser) ...[
                _AvatarA(color: ac.secretariatAccent),
                const SizedBox(width: Spacing.sm),
              ],
              Flexible(
                child: GestureDetector(
                  onLongPress: () => _showMessageMenu(context, msg),
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.76,
                    ),
                    decoration: BoxDecoration(
                      color: isUser ? ac.secretariatAccent : ac.surface,
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
                      border: isUser ? null : Border.all(color: ac.border),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: Spacing.md,
                      vertical: Spacing.sm + 2,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MarkdownBody(
                          data: msg.content,
                          styleSheet: MarkdownStyleSheet(
                            p: TextStyles.body(context).copyWith(color: isUser ? context.ac.onAccent : ac.ink, height: 1.6),
                            code: TextStyle(
                              fontFamily: FontFamily.mono,
                              fontSize: 12,
                              color: isUser
                                  ? context.ac.onAccent.withValues(alpha: 0.85)
                                  : ac.secretariatAccent,
                              backgroundColor: isUser
                                  ? Colors.white.withValues(alpha: 0.1)
                                  : ac.secretariatAccentLight,
                            ),
                          ),
                          selectable: true,
                        ),
                        if (msg.actions != null)
                          ...msg.actions!.map(
                            (action) => Padding(
                              padding: const EdgeInsets.only(top: Spacing.sm),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: Spacing.sm,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: ac.secretariatAccentLight,
                                  borderRadius: BorderRadius.circular(
                                    RadiusAmiin.sm,
                                  ),
                                ),
                                child: Text(
                                  ChatController.actionLabel(action.name),
                                  style: TextStyles.cardTitle(context).copyWith(fontSize: 11, color: ac.secretariatAccent, fontFamily: FontFamily.geoBold),
                                ),
                              ),
                            ),
                          ),
                        if (!isUser && chat.noteResults.containsKey(msg.id))
                          ChatNoteCard(
                            noteId: chat.noteResults[msg.id]!.id,
                            noteTitle: chat.noteResults[msg.id]!.title,
                            noteContent: chat.noteResults[msg.id]!.content,
                            isUpdate:
                                msg.actions?.any(
                                  (a) => a.name == 'update_note',
                                ) ??
                                false,
                          ),
                        if (!isUser && chat.eventResults.containsKey(msg.id))
                          ChatEventCard(
                            eventId: chat.eventResults[msg.id]!.id,
                            eventTitle: chat.eventResults[msg.id]!.title,
                            eventDate: chat.eventResults[msg.id]!.date,
                            isUpdate:
                                msg.actions?.any(
                                  (a) => a.name == 'update_event',
                                ) ??
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
        // Heure + bouton écoute
        Padding(
          padding: EdgeInsets.only(
            left: isUser ? 0 : 36,
            right: isUser ? 36 : 0,
            bottom: Spacing.md,
          ),
          child: Row(
            mainAxisAlignment: isUser
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              Text(
                DateFormat('HH:mm').format(msg.timestamp),
                style: TextStyles.sourceRef(context),
              ),
              if (!isUser && msg.content.isNotEmpty) ...[
                const SizedBox(width: Spacing.sm),
                InkWell(
                  onTap: () => _speakingMsgId == msg.id
                      ? _stopSpeaking()
                      : _speak(msg.content, msgId: msg.id),
                  borderRadius: BorderRadius.circular(RadiusAmiin.md),
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: Icon(
                      _speakingMsgId == msg.id
                          ? Icons.stop_circle_outlined
                          : Icons.volume_up_outlined,
                      size: 15,
                      color: _speakingMsgId == msg.id
                          ? ac.secretariatAccent
                          : ac.muted,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (!isUser && chat.messageUsage.containsKey(msg.id))
          _buildUsageBar(chat.messageUsage[msg.id]!, ac),
        if (!isUser &&
            chat.pendingDeletionMsgId == msg.id &&
            chat.pendingDeletions.isNotEmpty)
          ChatDeleteConfirm(
            descriptions: chat.pendingDeletions
                .map((p) => p.description)
                .toList(),
            onConfirm: chat.confirmPendingDeletions,
            onDismiss: chat.dismissPendingDeletions,
          ),
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

  Widget _buildUsageBar(Map<String, dynamic> usage, AmiinThemeColors ac) {
    final claudeIn = usage['claude_input'] as int? ?? 0;
    final claudeOut = usage['claude_output'] as int? ?? 0;
    final cacheRead = usage['claude_cache_read'] as int? ?? 0;
    final jinaTokens = usage['jina_tokens'] as int? ?? 0;
    final tools = (usage['tools'] as List?)?.cast<String>() ?? const <String>[];

    final parts = <String>[
      '↑$claudeIn ↓$claudeOut',
      if (cacheRead > 0) '⊙ $cacheRead',
      if (jinaTokens > 0) '· $jinaTokens',
      if (tools.isNotEmpty)
        '· ${tools.map(ChatController.actionLabel).join(', ')}',
    ];

    return Padding(
      padding: const EdgeInsets.only(left: 44, bottom: 6),
      child: Text(
        parts.join(' '),
        style: TextStyles.sourceRef(context).copyWith(color: ac.muted.withValues(alpha: 0.6)),
      ),
    );
  }

  // ── Barre de saisie ────────────────────────────────────────────────────────

  Widget _buildInputBar(
    EdgeInsets insets,
    ChatController chat,
    AmiinThemeColors ac,
  ) {
    return Container(
      padding: EdgeInsets.only(
        left: Spacing.md,
        right: Spacing.md,
        top: Spacing.sm,
        bottom: insets.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: ac.surface,
        border: Border(top: BorderSide(color: ac.border, width: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              maxLines: null,
              maxLength: 1000,
              onChanged: (_) => _dictated = false,
              onSubmitted: (_) => _sendMessage(),
              decoration: InputDecoration(
                hintText: _isListening
                    ? 'En écoute… tapez à nouveau le micro pour arrêter'
                    : 'Écrivez votre question…',
                hintStyle: TextStyles.bodyMuted(context),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(RadiusAmiin.xl),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: _isListening
                    ? context.ac.secretariatAccentLight.withValues(alpha: 0.5)
                    : ac.surface2,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: Spacing.md,
                  vertical: Spacing.sm,
                ),
              ),
              buildCounter:
                  (
                    context, {
                    required currentLength,
                    required isFocused,
                    maxLength,
                  }) {
                    if (currentLength < 900 || maxLength == null) return null;
                    return Text(
                      '$currentLength / $maxLength',
                      style: TextStyles.sourceRef(context).copyWith(color: currentLength >= maxLength
                            ? context.ac.alertColor
                            : ac.muted),
                    );
                  },
            ),
          ),
          const SizedBox(width: Spacing.sm),

          // Micro
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
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _isListening
                          ? context.ac.secretariatAccent
                          : context.ac.secretariatAccent.withValues(
                              alpha: 0.12,
                            ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isListening ? Icons.mic : Icons.mic_none,
                      color: _isListening
                          ? context.ac.onAccent
                          : context.ac.secretariatAccent,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ),

          const SizedBox(width: Spacing.sm),

          // Stop ou Send
          if (chat.isBusy)
            Semantics(
              button: true,
              label: 'Arrêter la réponse',
              child: Material(
                color: ac.muted.withValues(alpha: 0.15),
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: _cancelRequest,
                  customBorder: const CircleBorder(),
                  child: SizedBox(
                    width: 42,
                    height: 42,
                    child: Icon(Icons.stop_rounded, color: ac.muted, size: 22),
                  ),
                ),
              ),
            )
          else
            Semantics(
              button: true,
              label: 'Envoyer le message',
              child: Material(
                color: context.ac.secretariatAccent,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: _sendMessage,
                  customBorder: const CircleBorder(),
                  child: SizedBox(
                    width: 42,
                    height: 42,
                    child: Center(
                      child: SvgPicture.string(AmiinSvgIcons.send, width: 18, height: 18),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Menu contextuel ────────────────────────────────────────────────────────

  void _showMessageMenu(BuildContext context, ChatMessage msg) {
    HapticFeedback.mediumImpact();
    final ac = context.ac;
    showModalBottomSheet(
      context: context,
      backgroundColor: ac.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 32,
              height: 3,
              decoration: BoxDecoration(
                color: ac.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              leading: Icon(Icons.copy_outlined, color: ac.secretariatAccent),
              title: Text(
                'Copier',
                style: TextStyles.cardTitle(context),
              ),
              onTap: () {
                Navigator.pop(context);
                Clipboard.setData(ClipboardData(text: msg.content));
                AmiinToast.show(context, 'Message copié');
              },
            ),
            if (msg.role != 'user')
              ListTile(
                leading: Icon(
                  Icons.volume_up_outlined,
                  color: ac.secretariatAccent,
                ),
                title: Text(
                  'Écouter',
                  style: TextStyles.cardTitle(context),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _speak(msg.content, msgId: msg.id);
                },
              ),
            if (msg.role == 'user')
              ListTile(
                leading: Icon(
                  Icons.refresh_outlined,
                  color: ac.secretariatAccent,
                ),
                title: Text(
                  'Retenter',
                  style: TextStyles.cardTitle(context),
                ),
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

  // ── État vide ──────────────────────────────────────────────────────────────

  Widget _buildEmptyState(ChatController chat, AmiinThemeColors ac) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Spacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const AmiinLogo(size: 52, variant: AmiinLogoVariant.turquoise),
            const SizedBox(height: Spacing.lg),
            Text(
              'Bonjour — je suis Amiin',
              style: TextStyles.screenTitle(context).copyWith(fontSize: 20, letterSpacing: -0.3),
            ),
            const SizedBox(height: Spacing.sm),
            Text(
              'Posez-moi une question sur vos démarches administratives,\nvotre agenda ou les services publics de Djibouti.',
              style: TextStyle(
                fontFamily: FontFamily.sansLight,
                fontSize: 14,
                color: ac.muted,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: Spacing.xl),
            ..._starterQuestions.map(
              (q) => Padding(
                padding: const EdgeInsets.only(bottom: Spacing.sm),
                child: Material(
                  color: ac.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(RadiusAmiin.md),
                    side: BorderSide(color: ac.border),
                  ),
                  child: InkWell(
                    onTap: () => _sendMessage(q),
                    borderRadius: BorderRadius.circular(RadiusAmiin.md),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.lg,
                        vertical: Spacing.sm + 2,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 11,
                            color: ac.secretariatAccent,
                          ),
                          const SizedBox(width: Spacing.sm),
                          Flexible(
                            child: Text(
                              q,
                              style: TextStyles.body(context).copyWith(fontSize: 13),
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

}

// ── Avatar Amiin ───────────────────────────────────────────────────────────────

class _AvatarA extends StatelessWidget {
  final Color color;
  const _AvatarA({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Center(
        child: Text(
          'A',
          style: TextStyles.cardTitle(context).copyWith(fontSize: 12, color: context.ac.onAccent, fontFamily: FontFamily.geoBold),
        ),
      ),
    );
  }
}

// ── Bulle de réflexion ──────────────────────────────────────────────────────

class _ThinkingBubble extends StatefulWidget {
  final Color color;
  const _ThinkingBubble({required this.color});

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
          (c) => Tween(
            begin: 0.0,
            end: -5.0,
          ).animate(CurvedAnimation(parent: c, curve: Curves.easeInOut)),
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
    final ac = context.ac;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: Spacing.md),
      decoration: BoxDecoration(
        color: ac.surface,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(RadiusAmiin.lg),
          topRight: Radius.circular(RadiusAmiin.lg),
          bottomLeft: Radius.circular(4),
          bottomRight: Radius.circular(RadiusAmiin.lg),
        ),
        border: Border.all(color: ac.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          return AnimatedBuilder(
            animation: _offsets[i],
            builder: (_, __) => Transform.translate(
              offset: Offset(0, _offsets[i].value),
              child: Container(
                width: 6,
                height: 6,
                margin: EdgeInsets.only(right: i < 2 ? 5 : 0),
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.6),
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
