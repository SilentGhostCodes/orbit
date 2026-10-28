package app.orbit.client

import android.content.Context
import java.io.File

/**
 * geosite.dat and geoip.dat for Xray, which reads them from disk: copied out of the APK's Flutter
 * assets (assets/xray, trimmed in CI) once per install or update.
 */
object GeoFiles {
    private val names = listOf("geosite.dat", "geoip.dat")

    @Synchronized
    fun dir(ctx: Context): File {
        val dir = File(ctx.filesDir, "xray-assets")
        val stamp = File(dir, "stamp")
        val installed = ctx.packageManager.getPackageInfo(ctx.packageName, 0).lastUpdateTime.toString()
        if (stamp.exists() && stamp.readText() == installed && names.all { File(dir, it).exists() }) return dir
        dir.mkdirs()
        for (name in names) {
            val target = File(dir, name)
            val partial = File(dir, "$name.part")
            ctx.assets.open("flutter_assets/assets/xray/$name").use { input ->
                partial.outputStream().use { input.copyTo(it) }
            }
            partial.renameTo(target)
        }
        stamp.writeText(installed)
        return dir
    }
}
