package com.tareq.screen_guardian.dns

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Log
import com.tareq.screen_guardian.MainActivity
import com.tareq.screen_guardian.enforcement.SessionStore
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/**
 * DNS-only local VPN.
 *
 * The tunnel only routes the single fake resolver address ([FAKE_DNS]) so
 * regular traffic never enters the tunnel – there is no performance penalty
 * and nothing leaves the device. Every DNS query the system sends to the fake
 * resolver is intercepted here, checked against [BlockList] and either
 * answered with NXDOMAIN or forwarded to a family-safe upstream resolver.
 * Upstream answers are inspected as well so blocked IPs are never returned.
 */
class DnsFilterVpnService : VpnService() {

    companion object {
        const val ACTION_START = "com.tareq.screen_guardian.dns.START"
        const val ACTION_STOP = "com.tareq.screen_guardian.dns.STOP"
        private const val TAG = "DnsFilter"
        private const val CHANNEL_ID = "guardian_dns"
        private const val NOTIF_ID = 1002
        private const val TUN_ADDRESS = "10.111.222.1"
        private const val FAKE_DNS = "10.111.222.2"

        @Volatile
        var isRunning = false
    }

    private var tun: ParcelFileDescriptor? = null
    private var readerThread: Thread? = null
    private val running = AtomicBoolean(false)
    private val pool = Executors.newFixedThreadPool(8)
    private val writeLock = Any()
    private lateinit var blockList: BlockList
    private var blockedCount = 0L

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopVpn()
                stopSelf()
                return START_NOT_STICKY
            }
            else -> {
                val s = SessionStore.load(this)
                if (!s.active || !s.dnsFilterEnabled) {
                    stopVpn()
                    stopSelf()
                    return START_NOT_STICKY
                }
                blockList = BlockList(s.blockedDomains, s.blockedIps)
                startVpn()
                return START_STICKY
            }
        }
    }

    override fun onRevoke() {
        Log.w(TAG, "VPN revoked by user/system")
        stopVpn()
        super.onRevoke()
    }

    override fun onDestroy() {
        stopVpn()
        pool.shutdownNow()
        super.onDestroy()
    }

    // ----------------------------------------------------------- lifecycle

    private fun startVpn() {
        if (running.get()) return
        createChannel()
        startInForeground()
        val builder = Builder()
            .setSession("Screen Guardian Safe DNS")
            .addAddress(TUN_ADDRESS, 32)
            .addDnsServer(FAKE_DNS)
            .addRoute(FAKE_DNS, 32)
            .setMtu(1500)
            .setBlocking(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) builder.setMetered(false)
        val pfd = try {
            builder.establish()
        } catch (e: Exception) {
            Log.e(TAG, "establish failed", e)
            null
        } ?: run {
            stopSelf()
            return
        }
        tun = pfd
        running.set(true)
        isRunning = true
        readerThread = Thread({ readLoop(pfd) }, "guardian-dns").also { it.start() }
        Log.i(TAG, "DNS filter started")
    }

    private fun stopVpn() {
        if (!running.getAndSet(false)) return
        isRunning = false
        readerThread?.interrupt()
        try {
            tun?.close()
        } catch (_: Exception) {
        }
        tun = null
        try {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } catch (_: Exception) {
        }
        Log.i(TAG, "DNS filter stopped; blocked=$blockedCount")
    }

    // -------------------------------------------------------------- engine

    private fun readLoop(pfd: ParcelFileDescriptor) {
        val input = FileInputStream(pfd.fileDescriptor)
        val output = FileOutputStream(pfd.fileDescriptor)
        val buf = ByteArray(32767)
        while (running.get() && !Thread.currentThread().isInterrupted) {
            val n = try {
                input.read(buf)
            } catch (e: Exception) {
                if (running.get()) Log.w(TAG, "tun read failed", e)
                break
            }
            if (n <= 0) continue
            val dgram = DnsPacket.parseIpv4Udp(buf, n) ?: continue
            if (dgram.dstPort != 53) continue
            val packet = dgram
            pool.execute { handleQuery(packet, output) }
        }
    }

    private fun handleQuery(q: DnsPacket.UdpDatagram, out: FileOutputStream) {
        val name = DnsPacket.queryName(q.payload)
        val reply: ByteArray = if (name != null && blockList.isDomainBlocked(name)) {
            blockedCount++
            Log.d(TAG, "blocked domain $name")
            DnsPacket.nxDomain(q.payload)
        } else {
            val upstream = forward(q.payload) ?: return
            val ips = DnsPacket.answerIps(upstream)
            if (ips.any { blockList.isIpBlocked(it) }) {
                blockedCount++
                Log.d(TAG, "blocked ip for $name -> $ips")
                DnsPacket.nxDomain(q.payload)
            } else {
                upstream
            }
        }
        val packet = DnsPacket.buildIpv4Udp(q.dstIp, q.dstPort, q.srcIp, q.srcPort, reply)
        synchronized(writeLock) {
            try {
                out.write(packet)
            } catch (e: Exception) {
                Log.w(TAG, "tun write failed", e)
            }
        }
    }

    /** Sends the raw DNS query to the first upstream that answers. */
    private fun forward(query: ByteArray): ByteArray? {
        for (server in BlockList.UPSTREAM_DNS) {
            var socket: DatagramSocket? = null
            try {
                socket = DatagramSocket()
                protect(socket) // bypass the tunnel for our own upstream traffic
                socket.soTimeout = 3000
                socket.send(DatagramPacket(query, query.size, InetSocketAddress(InetAddress.getByName(server), 53)))
                val resp = ByteArray(4096)
                val dp = DatagramPacket(resp, resp.size)
                socket.receive(dp)
                return resp.copyOf(dp.length)
            } catch (e: Exception) {
                Log.v(TAG, "upstream $server failed: ${e.message}")
            } finally {
                socket?.close()
            }
        }
        return null
    }

    // -------------------------------------------------------- notification

    private fun createChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Safe DNS filter", NotificationManager.IMPORTANCE_MIN).apply {
                setShowBadge(false)
            },
        )
    }

    private fun startInForeground() {
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION") Notification.Builder(this)
        }
        val n = builder
            .setContentTitle("Safe browsing is on")
            .setContentText("Harmful websites are being blocked")
            .setSmallIcon(android.R.drawable.ic_secure)
            .setOngoing(true)
            .setContentIntent(open)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(NOTIF_ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIF_ID, n)
        }
    }
}
