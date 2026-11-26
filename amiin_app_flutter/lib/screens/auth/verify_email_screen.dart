// ─── VerifyEmailScreen ────────────────────────────────────────────────────────
// Saisie du code à 6 chiffres envoyé par e-mail à l'inscription. Le routeur
// garde l'utilisateur ici tant que son adresse n'est pas vérifiée ; une fois le
// code accepté, authService notifie et le routeur l'envoie sur /home.

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/auth_service.dart';
import '../../theme/colors.dart';
import '../../theme/spacing.dart';
import '../../theme/typography.dart';
import '../../widgets/amiin_logo.dart';
import 'auth_widgets.dart';

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  static const _resendDelay = 60; // secondes, aligné sur la limite serveur

  final _formKey  = GlobalKey<FormState>();
  final _codeCtrl = TextEditingController();

  bool    _loading = false;
  bool    _sending = false;
  String? _error;
  String? _info;
  int     _cooldown = _resendDelay; // un code vient de partir à l'inscription
  Timer?  _timer;

  @override
  void initState() {
    super.initState();
    _startCooldown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _codeCtrl.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _cooldown = _resendDelay);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() => _cooldown--);
      if (_cooldown <= 0) t.cancel();
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() { _loading = true; _error = null; _info = null; });
    try {
      await authService.verifyEmail(_codeCtrl.text.trim());
      // Le routeur redirige vers /home (refreshListenable)
    } on DioException catch (e) {
      setState(() => _error = authErrorMessage(e));
    } catch (_) {
      setState(() => _error = 'Une erreur inattendue est survenue.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    setState(() { _sending = true; _error = null; _info = null; });
    try {
      await authService.resendVerificationCode();
      setState(() => _info = 'Un nouveau code vient de vous être envoyé.');
      _startCooldown();
    } on DioException catch (e) {
      setState(() => _error = authErrorMessage(e));
    } catch (_) {
      setState(() => _error = 'Une erreur inattendue est survenue.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = authService.currentUser?.email ?? '';
    final muted = ColorsAmiin.onDark.withValues(alpha: 0.55);

    return Scaffold(
      backgroundColor: ColorsAmiin.encreNuit,
      body: AuthBackdrop(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: Spacing.xxxl),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  const Center(
                    child: AmiinLogo(size: 48, variant: AmiinLogoVariant.turquoise),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Vérifiez votre e-mail',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: FontFamily.geo,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: ColorsAmiin.onDark,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text.rich(
                    TextSpan(children: [
                      const TextSpan(text: 'Nous avons envoyé un code à 6 chiffres à\n'),
                      TextSpan(
                        text: email,
                        style: TextStyle(
                          fontFamily: FontFamily.geoMedium,
                          color: ColorsAmiin.onDark,
                        ),
                      ),
                      const TextSpan(text: '\nPensez à regarder dans les courriers indésirables.'),
                    ]),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: FontFamily.sans,
                      fontSize: 14,
                      height: 1.5,
                      color: muted,
                    ),
                  ),
                  const SizedBox(height: 32),

                  AuthDarkField(
                    controller: _codeCtrl,
                    label: 'Code de vérification',
                    hint: '123456',
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    validator: (v) {
                      final code = v?.trim() ?? '';
                      if (!RegExp(r'^\d{6}$').hasMatch(code)) return 'Le code comporte 6 chiffres';
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),

                  if (_error != null) ...[
                    AuthErrorBanner(_error!),
                    const SizedBox(height: 16),
                  ],
                  if (_info != null) ...[
                    Text(
                      _info!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: FontFamily.sans,
                        fontSize: 13,
                        color: ColorsAmiin.turquoiseMid,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  AuthPrimaryButton(label: 'Valider', loading: _loading, onPressed: _submit),
                  const SizedBox(height: 20),

                  Center(
                    child: TextButton(
                      onPressed: (_cooldown > 0 || _sending) ? null : _resend,
                      style: TextButton.styleFrom(
                        foregroundColor: ColorsAmiin.turquoiseMid,
                        disabledForegroundColor: muted,
                      ),
                      child: Text(
                        _cooldown > 0
                            ? 'Renvoyer le code (${_cooldown}s)'
                            : (_sending ? 'Envoi…' : 'Renvoyer le code'),
                        style: TextStyle(fontFamily: FontFamily.geoMedium, fontSize: 14),
                      ),
                    ),
                  ),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        HapticFeedback.selectionClick();
                        authService.logout(); // le routeur renvoie sur /login
                      },
                      style: TextButton.styleFrom(foregroundColor: muted),
                      child: Text(
                        'Utiliser une autre adresse',
                        style: TextStyle(fontFamily: FontFamily.sans, fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
