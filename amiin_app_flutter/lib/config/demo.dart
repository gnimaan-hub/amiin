// ─── Mode démo ───────────────────────────────────────────────────────────────
// Activé à la compilation de la démo web publiée sur WebSense :
//   flutter build web --dart-define=AMIIN_DEMO=true …
// En démo, l'inscription est fermée (accès sur invitation) ; le reste de
// l'application est identique.

const bool kAmiinDemo = bool.fromEnvironment('AMIIN_DEMO');
