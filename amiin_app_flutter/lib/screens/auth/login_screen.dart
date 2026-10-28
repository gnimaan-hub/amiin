// ─── LoginScreen ─────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../../theme/spacing.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../theme/colors.dart';
import '../../theme/typography.dart';
import '../../services/auth_service.dart';
import '../../widgets/amiin_logo.dart';
import 'auth_widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey   = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl  = TextEditingController();

  bool    _loading      = false;
  bool    _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() { _loading = true; _error = null; });
    try {
      await authService.login(
        email:    _emailCtrl.text.trim(),
        password: _passCtrl.text,
      );
      // GoRouter redirige automatiquement vers /home via refreshListenable
    } on DioException catch (e) {
      setState(() { _error = authErrorMessage(e); });
    } catch (_) {
      setState(() { _error = 'Une erreur inattendue est survenue.'; });
    } finally {
      if (mounted) setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ColorsAmiin.encreNuit,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: Spacing.xxxl),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),

                // ── Logo ──────────────────────────────────────────────────
                const Center(
                  child: AmiinLogo(size: 56, variant: AmiinLogoVariant.turquoise),
                ),
                const SizedBox(height: 28),

                // ── Titre ─────────────────────────────────────────────────
                Text(
                  'Bon retour',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: FontFamily.geo,
                    fontSize: FontSize.xxl,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: ColorsAmiin.onDark,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Connectez-vous à votre compte Amiin',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: FontFamily.sans,
                    fontSize: 14,
                    color: ColorsAmiin.onDark.withValues(alpha: 0.45),
                  ),
                ),
                const SizedBox(height: 40),

                // ── Email ─────────────────────────────────────────────────
                AuthDarkField(
                  controller: _emailCtrl,
                  label: 'Adresse e-mail',
                  hint: 'vous@example.com',
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Champ requis';
                    if (!v.contains('@')) return 'Email invalide';
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // ── Mot de passe ──────────────────────────────────────────
                AuthDarkField(
                  controller: _passCtrl,
                  label: 'Mot de passe',
                  hint: '••••••••',
                  obscureText: !_showPassword,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                      color: ColorsAmiin.onDark.withValues(alpha: 0.45),
                    ),
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Champ requis';
                    return null;
                  },
                ),
                const SizedBox(height: 10),

                // ── Mot de passe oublié ───────────────────────────────────
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => _showForgotDialog(context),
                    style: TextButton.styleFrom(
                      foregroundColor: ColorsAmiin.turquoiseMid,
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                    ),
                    child: Text(
                      'Mot de passe oublié ?',
                      style: TextStyle(fontFamily: FontFamily.sans, fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // ── Erreur ────────────────────────────────────────────────
                if (_error != null) ...[
                  AuthErrorBanner(_error!),
                  const SizedBox(height: 16),
                ],

                // ── Bouton Se connecter ───────────────────────────────────
                AuthPrimaryButton(
                  label: 'Se connecter',
                  loading: _loading,
                  onPressed: _submit,
                ),
                const SizedBox(height: 28),

                // ── Divider ───────────────────────────────────────────────
                const AuthDivider(),
                const SizedBox(height: 24),

                // ── Lien créer un compte ──────────────────────────────────
                TextButton(
                  onPressed: () => context.go('/register'),
                  style: TextButton.styleFrom(
                    foregroundColor: ColorsAmiin.onDark,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(RadiusAmiin.lg),
                      side: BorderSide(
                        color: ColorsAmiin.onDark.withValues(alpha: 0.18),
                      ),
                    ),
                  ),
                  child: Text(
                    'Créer un compte',
                    style: TextStyle(fontFamily: FontFamily.geoMedium, fontSize: 15),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Réinitialisation en deux étapes : e-mail → code à 6 chiffres reçu par
  /// e-mail + nouveau mot de passe.
  void _showForgotDialog(BuildContext context) {
    final emailCtrl = TextEditingController(text: _emailCtrl.text.trim());
    final codeCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    bool codeSent = false;
    bool busy = false;
    String? error;
    String? info;

    final textStyle = TextStyle(fontFamily: FontFamily.sans, color: ColorsAmiin.onDark);
    InputDecoration deco(String label) => InputDecoration(
          labelText: label,
          labelStyle: TextStyle(color: ColorsAmiin.onDark.withValues(alpha: 0.6)),
        );

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          Future<void> run(Future<void> Function() action) async {
            setState(() { busy = true; error = null; });
            try {
              await action();
            } on DioException catch (e) {
              error = authErrorMessage(e);
            } finally {
              if (ctx.mounted) setState(() => busy = false);
            }
          }

          return AlertDialog(
            backgroundColor: ColorsAmiin.darkMid,
            title: Text(
              'Mot de passe oublié',
              style: TextStyle(fontFamily: FontFamily.geo, color: ColorsAmiin.onDark),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    codeSent
                        ? (info ?? 'Saisissez le code reçu par e-mail et votre nouveau mot de passe.')
                        : 'Nous allons vous envoyer un code de réinitialisation par e-mail.',
                    style: textStyle.copyWith(color: ColorsAmiin.onDark.withValues(alpha: 0.7)),
                  ),
                  const SizedBox(height: Spacing.md),
                  TextField(
                    controller: emailCtrl,
                    enabled: !codeSent && !busy,
                    keyboardType: TextInputType.emailAddress,
                    style: textStyle,
                    decoration: deco('E-mail'),
                  ),
                  if (codeSent) ...[
                    TextField(
                      controller: codeCtrl,
                      enabled: !busy,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      style: textStyle,
                      decoration: deco('Code à 6 chiffres'),
                    ),
                    TextField(
                      controller: passCtrl,
                      enabled: !busy,
                      obscureText: true,
                      style: textStyle,
                      decoration: deco('Nouveau mot de passe (8 caractères min.)'),
                    ),
                  ],
                  if (error != null) ...[
                    const SizedBox(height: Spacing.sm),
                    Text(error!, style: textStyle.copyWith(color: Colors.redAccent)),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(ctx),
                child: Text('Annuler',
                    style: TextStyle(color: ColorsAmiin.onDark.withValues(alpha: 0.7))),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () {
                        final email = emailCtrl.text.trim();
                        if (!codeSent) {
                          if (!email.contains('@')) {
                            setState(() => error = 'Adresse e-mail invalide.');
                            return;
                          }
                          run(() async {
                            await authService.forgotPassword(email);
                            codeSent = true;
                            info = 'Si un compte existe pour $email, un code vient d\'y être '
                                'envoyé (valable 30 min). Saisissez-le avec votre nouveau mot de passe.';
                          });
                        } else {
                          if (passCtrl.text.length < 8) {
                            setState(() => error = 'Le mot de passe doit comporter au moins 8 caractères.');
                            return;
                          }
                          run(() async {
                            await authService.resetPassword(
                              email: email,
                              code: codeCtrl.text.trim(),
                              newPassword: passCtrl.text,
                            );
                            _emailCtrl.text = email;
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (mounted) {
                              ScaffoldMessenger.of(this.context).showSnackBar(const SnackBar(
                                content: Text('Mot de passe modifié — connectez-vous.'),
                              ));
                            }
                          });
                        }
                      },
                child: Text(
                  codeSent ? 'Valider' : 'Envoyer le code',
                  style: TextStyle(color: ColorsAmiin.turquoiseMid, fontFamily: FontFamily.geo),
                ),
              ),
            ],
          );
        },
      ),
    ).whenComplete(() {
      emailCtrl.dispose();
      codeCtrl.dispose();
      passCtrl.dispose();
    });
  }
}
