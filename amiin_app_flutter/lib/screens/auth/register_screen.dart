// ─── RegisterScreen ───────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import '../../theme/spacing.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../../theme/colors.dart';
import '../../theme/typography.dart';
import '../../services/auth_service.dart';
import '../../widgets/amiin_logo.dart';
import 'auth_widgets.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey     = GlobalKey<FormState>();
  final _nameCtrl    = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _passCtrl    = TextEditingController();
  final _confirmCtrl = TextEditingController();

  bool    _loading     = false;
  bool    _showPass    = false;
  bool    _showConfirm = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() { _loading = true; _error = null; });
    try {
      await authService.register(
        email:       _emailCtrl.text.trim(),
        password:    _passCtrl.text,
        displayName: _nameCtrl.text.trim(),
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
                const SizedBox(height: 16),

                // ── Logo ──────────────────────────────────────────────────
                const Center(
                  child: AmiinLogo(size: 48, variant: AmiinLogoVariant.turquoise),
                ),
                const SizedBox(height: 20),

                // ── Titre ─────────────────────────────────────────────────
                Text(
                  'Créer un compte',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: FontFamily.geo,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: ColorsAmiin.onDark,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Votre assistant national vous attend',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: FontFamily.sans,
                    fontSize: 14,
                    color: ColorsAmiin.onDark.withValues(alpha: 0.45),
                  ),
                ),
                const SizedBox(height: 36),

                // ── Nom d'affichage ───────────────────────────────────────
                AuthDarkField(
                  controller: _nameCtrl,
                  label: 'Prénom ou surnom',
                  hint: 'Comment vous appeler ?',
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Champ requis';
                    if (v.trim().length < 2) return 'Au moins 2 caractères';
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // ── Email ─────────────────────────────────────────────────
                AuthDarkField(
                  controller: _emailCtrl,
                  label: 'Adresse e-mail',
                  hint: 'vous@example.com',
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Champ requis';
                    if (!v.contains('@') || !v.contains('.')) return 'Email invalide';
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // ── Mot de passe ──────────────────────────────────────────
                AuthDarkField(
                  controller: _passCtrl,
                  label: 'Mot de passe',
                  hint: '8 caractères minimum',
                  obscureText: !_showPass,
                  textInputAction: TextInputAction.next,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showPass
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                      color: ColorsAmiin.onDark.withValues(alpha: 0.45),
                    ),
                    onPressed: () => setState(() => _showPass = !_showPass),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Champ requis';
                    if (v.length < 8) return 'Au moins 8 caractères';
                    return null;
                  },
                ),
                const SizedBox(height: 14),

                // ── Confirmation ──────────────────────────────────────────
                AuthDarkField(
                  controller: _confirmCtrl,
                  label: 'Confirmer le mot de passe',
                  hint: '••••••••',
                  obscureText: !_showConfirm,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _showConfirm
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                      color: ColorsAmiin.onDark.withValues(alpha: 0.45),
                    ),
                    onPressed: () => setState(() => _showConfirm = !_showConfirm),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Champ requis';
                    if (v != _passCtrl.text) return 'Les mots de passe ne correspondent pas';
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                // ── Erreur ────────────────────────────────────────────────
                if (_error != null) ...[
                  AuthErrorBanner(_error!),
                  const SizedBox(height: 16),
                ],

                // ── Bouton créer ──────────────────────────────────────────
                AuthPrimaryButton(
                  label: 'Créer mon compte',
                  loading: _loading,
                  onPressed: _submit,
                ),
                const SizedBox(height: 20),

                // ── Lien déjà un compte ───────────────────────────────────
                Center(
                  child: TextButton(
                    onPressed: () => context.go('/login'),
                    style: TextButton.styleFrom(
                      foregroundColor: ColorsAmiin.turquoiseMid,
                      padding: const EdgeInsets.symmetric(horizontal: Spacing.sm, vertical: 6),
                    ),
                    child: Text(
                      'J\'ai déjà un compte',
                      style: TextStyle(fontFamily: FontFamily.geoMedium, fontSize: 14),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ── CGU ───────────────────────────────────────────────────
                Text(
                  'En créant un compte vous acceptez les conditions\nd\'utilisation d\'Amiin.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: FontFamily.sans,
                    fontSize: 11,
                    height: 1.5,
                    color: ColorsAmiin.onDark.withValues(alpha: 0.3),
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
}
