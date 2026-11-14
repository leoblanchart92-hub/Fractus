// Le service de premier plan : il garde le flux d'événements du PC ouvert
// même quand l'appli est fermée, et prévient par notification quand Fractus
// attend ton accord — avec Autoriser / Refuser / Toujours directement dedans.
// Tout est natif (pas d'isolat Dart) : léger, et Android le laisse tourner.

package app.fractus.fractus_mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import org.json.JSONObject
import java.io.BufferedReader
import java.io.IOException
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL

/** La connexion au PC telle que l'appli Flutter l'a enregistrée (shared_preferences). */
object PcPrefs {
    data class Conn(val host: String, val port: Int, val token: String) {
        val base: String get() = "http://$host:$port"
    }

    private fun prefs(ctx: Context) = ctx.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    fun read(ctx: Context): Conn? {
        val p = prefs(ctx)
        val host = p.getString("flutter.host", "") ?: ""
        val token = p.getString("flutter.token", "") ?: ""
        if (host.isEmpty() || token.isEmpty()) return null
        val port = try {
            p.getLong("flutter.port", 7790L).toInt()
        } catch (_: ClassCastException) {
            p.getInt("flutter.port", 7790)
        }
        return Conn(host, port, token)
    }

    fun notifyEnabled(ctx: Context): Boolean = prefs(ctx).getBoolean("flutter.bg_notify", false)

    /** POST JSON vers le PC, avec le code. Lève en cas d'erreur. */
    fun post(conn: Conn, path: String, body: JSONObject) {
        val c = URL(conn.base + path).openConnection() as HttpURLConnection
        try {
            c.requestMethod = "POST"
            c.connectTimeout = 6000
            c.readTimeout = 10000
            c.doOutput = true
            c.setRequestProperty("Authorization", "Bearer ${conn.token}")
            c.setRequestProperty("Content-Type", "application/json")
            OutputStreamWriter(c.outputStream, Charsets.UTF_8).use { it.write(body.toString()) }
            if (c.responseCode >= 300) throw IOException("HTTP ${c.responseCode}")
        } finally {
            c.disconnect()
        }
    }
}

class FractusService : Service() {
    companion object {
        const val CH_STATUS = "fractus_status"
        const val CH_ASK = "fractus_ask"
        const val ID_STATUS = 1
        const val ID_ASK = 2

        @Volatile
        var running = false

        fun start(ctx: Context) {
            val i = Intent(ctx, FractusService::class.java)
            if (Build.VERSION.SDK_INT >= 26) ctx.startForegroundService(i) else ctx.startService(i)
        }

        fun stop(ctx: Context) {
            ctx.stopService(Intent(ctx, FractusService::class.java))
        }

        fun stateLabel(s: String): String = when (s) {
            "working" -> "travaille"
            "thinking" -> "réfléchit"
            "searching" -> "cherche"
            "approval" -> "attend ton accord"
            "question" -> "te pose une question"
            "error" -> "a rencontré une erreur"
            "finished" -> "a terminé"
            "ratelimit" -> "attend (quota)"
            "sleeping" -> "dort"
            else -> "est au repos"
        }
    }

    private var worker: Thread? = null

    @Volatile
    private var alive = false
    private var lastText = ""
    private var lastPending: String? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        channels()
        val n = statusNotification("Connexion au PC…")
        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(ID_STATUS, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(ID_STATUS, n)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (worker == null) {
            alive = true
            running = true
            worker = Thread({ loop() }, "fractus-events").apply {
                isDaemon = true
                start()
            }
        }
        return START_STICKY
    }

    override fun onDestroy() {
        alive = false
        running = false
        worker?.interrupt()
        worker = null
        nm().cancel(ID_ASK)
        super.onDestroy()
    }

    // ── Le flux du PC ────────────────────────────────────────────────────────

    private fun loop() {
        var backoff = 2L
        while (alive) {
            val c = PcPrefs.read(this)
            if (c == null) {
                show("Aucun PC configuré : ouvre Fractus pour te connecter")
                if (!sleep(10)) break
                continue
            }
            var conn: HttpURLConnection? = null
            try {
                conn = (URL("${c.base}/api/events").openConnection() as HttpURLConnection).apply {
                    setRequestProperty("Authorization", "Bearer ${c.token}")
                    setRequestProperty("Accept", "text/event-stream")
                    connectTimeout = 6000
                    readTimeout = 70000 // le PC envoie un « ping » toutes les 20 s
                }
                if (conn.responseCode != 200) throw IOException("HTTP ${conn.responseCode}")
                backoff = 2
                val reader = BufferedReader(InputStreamReader(conn.inputStream, Charsets.UTF_8))
                val data = StringBuilder()
                while (alive) {
                    val line = reader.readLine() ?: break
                    if (line.startsWith("data:")) {
                        data.append(line.substring(5).trim())
                    } else if (line.isEmpty() && data.isNotEmpty()) {
                        try {
                            handle(JSONObject(data.toString()), c)
                        } catch (_: Exception) {
                        }
                        data.setLength(0)
                    }
                }
            } catch (e: Exception) {
                if (!alive) break
                val why = if (e is IOException && e.message?.startsWith("HTTP 401") == true) "code refusé" else "PC injoignable"
                show("$why (${c.host}) · nouvel essai dans ${backoff} s")
            } finally {
                try {
                    conn?.disconnect()
                } catch (_: Exception) {
                }
            }
            if (!alive || !sleep(backoff)) break
            backoff = (backoff * 2).coerceAtMost(30)
        }
    }

    private fun sleep(seconds: Long): Boolean = try {
        Thread.sleep(seconds * 1000)
        true
    } catch (_: InterruptedException) {
        false
    }

    private fun handle(j: JSONObject, c: PcPrefs.Conn) {
        val state = j.optString("botState", "idle")
        val sessions = j.optJSONArray("sessions")
        var active = 0
        if (sessions != null) {
            for (i in 0 until sessions.length()) {
                if (sessions.getJSONObject(i).optBoolean("active")) active++
            }
        }
        val host = j.optString("host", c.host)
        val tail = if (active > 1) " · $active sessions" else ""
        show("$host · Fractus ${stateLabel(state)}$tail")

        val p = j.optJSONObject("pending")
        if (p == null) {
            if (lastPending != null) {
                nm().cancel(ID_ASK)
                lastPending = null
            }
            return
        }
        val id = p.optString("requestId", "")
        if (id.isEmpty() || id == lastPending) return
        lastPending = id
        ask(p, id)
    }

    // ── Les notifications ────────────────────────────────────────────────────

    private fun nm() = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    private fun channels() {
        if (Build.VERSION.SDK_INT < 26) return
        val m = nm()
        m.createNotificationChannel(
            NotificationChannel(CH_STATUS, "Fractus — connexion au PC", NotificationManager.IMPORTANCE_MIN).apply {
                description = "La connexion permanente au PC (discrète, sans son)"
                setShowBadge(false)
            }
        )
        m.createNotificationChannel(
            NotificationChannel(CH_ASK, "Fractus — demandes", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Quand Fractus attend ton accord ou te pose une question"
                enableVibration(true)
            }
        )
    }

    private fun flags(): Int =
        if (Build.VERSION.SDK_INT >= 23) PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        else PendingIntent.FLAG_UPDATE_CURRENT

    private fun openApp(): PendingIntent {
        val i = Intent(this, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        return PendingIntent.getActivity(this, 10, i, flags())
    }

    private fun decideIntent(requestId: String, decision: String, code: Int): PendingIntent {
        val i = Intent(this, FractusActionReceiver::class.java).apply {
            action = "app.fractus.DECIDE_$decision"
            putExtra("requestId", requestId)
            putExtra("decision", decision)
        }
        return PendingIntent.getBroadcast(this, code, i, flags())
    }

    private fun statusNotification(text: String) =
        NotificationCompat.Builder(this, CH_STATUS)
            .setSmallIcon(R.drawable.ic_stat_fractus)
            .setContentTitle("Fractus")
            .setContentText(text)
            .setContentIntent(openApp())
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .build()

    private fun show(text: String) {
        if (text == lastText) return
        lastText = text
        try {
            nm().notify(ID_STATUS, statusNotification(text))
        } catch (_: Exception) {
        }
    }

    private fun ask(p: JSONObject, id: String) {
        val project = p.optString("project", "Fractus")
        val isQuestion = p.optBoolean("isQuestion")
        val title: String
        val text: String
        if (isQuestion) {
            val q = p.optJSONArray("questions")?.optJSONObject(0)
            title = "$project te pose une question"
            text = q?.optString("question", "") ?: ""
        } else {
            val label = p.optString("label", "Permission")
            title = "$project — $label"
            text = p.optString("summary", "").ifEmpty { p.optString("tool", "") }
        }
        val b = NotificationCompat.Builder(this, CH_ASK)
            .setSmallIcon(R.drawable.ic_stat_fractus)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setContentIntent(openApp())
            .setAutoCancel(true)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
        if (isQuestion) {
            b.addAction(0, "Répondre", openApp())
        } else {
            b.addAction(0, "Autoriser", decideIntent(id, "allow", 1))
            b.addAction(0, "Refuser", decideIntent(id, "deny", 2))
            b.addAction(0, "Toujours", decideIntent(id, "always", 3))
        }
        try {
            nm().notify(ID_ASK, b.build())
        } catch (_: Exception) {
        }
    }
}

/** Les boutons de la notification : on répond au PC sans ouvrir l'appli. */
class FractusActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val requestId = intent.getStringExtra("requestId") ?: return
        val decision = intent.getStringExtra("decision") ?: return
        val conn = PcPrefs.read(context) ?: return
        val result = goAsync()
        Thread {
            try {
                PcPrefs.post(conn, "/api/approvals/decide", JSONObject().put("requestId", requestId).put("decision", decision))
            } catch (_: Exception) {
            }
            (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).cancel(FractusService.ID_ASK)
            result.finish()
        }.start()
    }
}

/** Au démarrage du téléphone : on relance le service si l'option est active. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        if (PcPrefs.notifyEnabled(context) && PcPrefs.read(context) != null) FractusService.start(context)
    }
}
