package com.soofiaa.aura

import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Datos de salud: la proteccion de pantalla empieza activada, antes
        // de dibujar nada. La app la apaga despues si la usuaria lo eligio
        // en Ajustes ("Ocultar Aura en Recientes").
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setScreenProtection" -> {
                        if (call.arguments == true) {
                            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        } else {
                            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                        }
                        result.success(null)
                    }
                    "openNotificationSettings" -> result.success(openNotificationSettings())
                    // HU-09: la clave que protege los respaldos de Drive se
                    // guarda como texto cifrado por el Keystore de Android;
                    // la app nunca la escribe en claro.
                    "keystoreEncrypt" -> {
                        val plaintext = call.arguments as? String
                        if (plaintext == null) {
                            result.error("keystore", "argumento invalido", null)
                        } else {
                            try {
                                result.success(keystoreEncrypt(plaintext))
                            } catch (e: Exception) {
                                result.error("keystore", e.message, null)
                            }
                        }
                    }
                    "keystoreDecrypt" -> {
                        val blob = call.arguments as? String
                        if (blob == null) {
                            result.error("keystore", "argumento invalido", null)
                        } else {
                            try {
                                result.success(keystoreDecrypt(blob))
                            } catch (e: Exception) {
                                result.error("keystore", e.message, null)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun openNotificationSettings(): Boolean {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(android.net.Uri.fromParts("package", packageName, null))
        }
        return try {
            startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (e: Exception) {
            false
        }
    }

    // --- Keystore (HU-09) -------------------------------------------------

    private fun keystoreKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator =
            KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return generator.generateKey()
    }

    private fun keystoreEncrypt(plaintext: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, keystoreKey())
        val ciphertext = cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(cipher.iv + ciphertext, Base64.NO_WRAP)
    }

    private fun keystoreDecrypt(blob: String): String {
        val bytes = Base64.decode(blob, Base64.NO_WRAP)
        val ivLength = 12 // El iv de GCM son 12 bytes (estandar).
        if (bytes.size <= ivLength) throw IllegalArgumentException("blob invalido")
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            keystoreKey(),
            GCMParameterSpec(128, bytes, 0, ivLength)
        )
        return String(cipher.doFinal(bytes, ivLength, bytes.size - ivLength), Charsets.UTF_8)
    }

    private companion object {
        const val CHANNEL = "com.soofiaa.aura/system"
        const val KEY_ALIAS = "aura_respaldos_drive_v1"
    }
}
