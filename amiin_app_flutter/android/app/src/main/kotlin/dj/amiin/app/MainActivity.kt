package dj.amiin.app

import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.StandardIntegrityManager.PrepareIntegrityTokenRequest
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenProvider
import com.google.android.play.core.integrity.StandardIntegrityManager.StandardIntegrityTokenRequest
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest

/**
 * Play Integrity (API « Standard ») : jeton prouvant au serveur que la requête
 * vient de l'app officielle, installée depuis le Play Store, sur un appareil
 * intègre. Appelé par lib/services/integrity_service.dart à l'inscription et
 * à la connexion ; vérifié côté serveur par integrity.py.
 */
class MainActivity : FlutterActivity() {
    private var provider: StandardIntegrityTokenProvider? = null
    private var providerProject = 0L

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dj.amiin.app/integrity")
            .setMethodCallHandler { call, result ->
                if (call.method != "token") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val project = (call.argument<Any>("cloudProjectNumber") as? Number)?.toLong() ?: 0L
                val data = call.argument<String>("requestData") ?: ""
                if (project <= 0L) {
                    result.success(null)
                    return@setMethodCallHandler
                }
                requestToken(project, sha256(data), retry = true) { token -> result.success(token) }
            }
    }

    /** Empreinte de la requête — même calcul que integrity.request_hash côté serveur. */
    private fun sha256(text: String): String =
        MessageDigest.getInstance("SHA-256")
            .digest(text.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }

    private fun requestToken(project: Long, hash: String, retry: Boolean, done: (String?) -> Unit) {
        val current = provider
        if (current == null || providerProject != project) {
            IntegrityManagerFactory.createStandard(applicationContext)
                .prepareIntegrityToken(
                    PrepareIntegrityTokenRequest.builder().setCloudProjectNumber(project).build()
                )
                .addOnSuccessListener { prepared ->
                    provider = prepared
                    providerProject = project
                    requestToken(project, hash, retry = false, done = done)
                }
                .addOnFailureListener { done(null) }
            return
        }
        current.request(StandardIntegrityTokenRequest.builder().setRequestHash(hash).build())
            .addOnSuccessListener { token -> done(token.token()) }
            .addOnFailureListener {
                // Fournisseur expiré : on le prépare à nouveau une fois
                provider = null
                if (retry) requestToken(project, hash, retry = false, done = done) else done(null)
            }
    }
}
