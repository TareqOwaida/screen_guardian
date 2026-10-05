package com.tareq.screen_guardian.dns

/** Minimal IPv4 / UDP / DNS parsing and building for the DNS filter. */
object DnsPacket {

    class UdpDatagram(
        val srcIp: ByteArray,
        val dstIp: ByteArray,
        val srcPort: Int,
        val dstPort: Int,
        val payload: ByteArray,
    )

    /** Returns the UDP datagram carried by an IPv4 packet, or null. */
    fun parseIpv4Udp(buf: ByteArray, len: Int): UdpDatagram? {
        if (len < 28) return null
        val version = (buf[0].toInt() shr 4) and 0x0F
        if (version != 4) return null
        val ihl = (buf[0].toInt() and 0x0F) * 4
        if (ihl < 20 || len < ihl + 8) return null
        val protocol = buf[9].toInt() and 0xFF
        if (protocol != 17) return null
        val totalLength = u16(buf, 2).coerceAtMost(len)
        val udpLen = u16(buf, ihl + 4)
        val payloadLen = (udpLen - 8).coerceAtMost(totalLength - ihl - 8)
        if (payloadLen <= 0) return null
        return UdpDatagram(
            srcIp = buf.copyOfRange(12, 16),
            dstIp = buf.copyOfRange(16, 20),
            srcPort = u16(buf, ihl),
            dstPort = u16(buf, ihl + 2),
            payload = buf.copyOfRange(ihl + 8, ihl + 8 + payloadLen),
        )
    }

    /** Builds a complete IPv4+UDP packet around [payload]. */
    fun buildIpv4Udp(srcIp: ByteArray, srcPort: Int, dstIp: ByteArray, dstPort: Int, payload: ByteArray): ByteArray {
        val udpLen = 8 + payload.size
        val total = 20 + udpLen
        val p = ByteArray(total)
        p[0] = 0x45
        p[1] = 0
        put16(p, 2, total)
        put16(p, 4, 0) // identification
        put16(p, 6, 0x4000) // don't fragment
        p[8] = 64 // ttl
        p[9] = 17 // udp
        System.arraycopy(srcIp, 0, p, 12, 4)
        System.arraycopy(dstIp, 0, p, 16, 4)
        put16(p, 10, checksum(p, 0, 20, 0))

        put16(p, 20, srcPort)
        put16(p, 22, dstPort)
        put16(p, 24, udpLen)
        put16(p, 26, 0)
        System.arraycopy(payload, 0, p, 28, payload.size)

        // UDP checksum over pseudo header + udp segment
        var sum = 0
        sum += u16(srcIp, 0) + u16(srcIp, 2) + u16(dstIp, 0) + u16(dstIp, 2)
        sum += 17 + udpLen
        var cs = checksum(p, 20, udpLen, sum)
        if (cs == 0) cs = 0xFFFF
        put16(p, 26, cs)
        return p
    }

    /** Extracts the first question name of a DNS message. */
    fun queryName(dns: ByteArray): String? {
        if (dns.size < 12) return null
        val qd = u16(dns, 4)
        if (qd < 1) return null
        val sb = StringBuilder()
        var i = 12
        var guard = 0
        while (i < dns.size && guard++ < 128) {
            val l = dns[i].toInt() and 0xFF
            if (l == 0) break
            if ((l and 0xC0) == 0xC0) return null // compression in question – unusual
            i++
            if (i + l > dns.size) return null
            if (sb.isNotEmpty()) sb.append('.')
            for (k in 0 until l) sb.append((dns[i + k].toInt() and 0xFF).toChar())
            i += l
        }
        return sb.toString()
    }

    /** All IPv4 addresses found in the answer section. */
    fun answerIps(dns: ByteArray): List<String> {
        val out = ArrayList<String>()
        if (dns.size < 12) return out
        val qd = u16(dns, 4)
        val an = u16(dns, 6)
        var i = 12
        for (q in 0 until qd) {
            i = skipName(dns, i) ?: return out
            i += 4
        }
        for (a in 0 until an) {
            i = skipName(dns, i) ?: return out
            if (i + 10 > dns.size) return out
            val type = u16(dns, i)
            val rdLen = u16(dns, i + 8)
            i += 10
            if (i + rdLen > dns.size) return out
            if (type == 1 && rdLen == 4) {
                out.add(
                    "${dns[i].toInt() and 0xFF}.${dns[i + 1].toInt() and 0xFF}." +
                        "${dns[i + 2].toInt() and 0xFF}.${dns[i + 3].toInt() and 0xFF}",
                )
            }
            i += rdLen
        }
        return out
    }

    /** Builds an NXDOMAIN reply for [query] (header + question copied). */
    fun nxDomain(query: ByteArray): ByteArray {
        val qEnd = (skipName(query, 12) ?: 12) + 4
        val len = qEnd.coerceAtMost(query.size)
        val r = query.copyOf(len)
        // QR=1, opcode copied, AA=0, TC=0, RD copied, RA=1, RCODE=3
        r[2] = ((r[2].toInt() and 0x79) or 0x80).toByte()
        r[3] = (0x80 or 0x03).toByte()
        put16(r, 4, 1) // qdcount
        put16(r, 6, 0)
        put16(r, 8, 0)
        put16(r, 10, 0)
        return r
    }

    // ------------------------------------------------------------ helpers

    private fun skipName(b: ByteArray, start: Int): Int? {
        var i = start
        var guard = 0
        while (i < b.size && guard++ < 128) {
            val l = b[i].toInt() and 0xFF
            if (l == 0) return i + 1
            if ((l and 0xC0) == 0xC0) return i + 2
            i += l + 1
        }
        return null
    }

    fun u16(b: ByteArray, off: Int): Int = ((b[off].toInt() and 0xFF) shl 8) or (b[off + 1].toInt() and 0xFF)

    private fun put16(b: ByteArray, off: Int, v: Int) {
        b[off] = ((v shr 8) and 0xFF).toByte()
        b[off + 1] = (v and 0xFF).toByte()
    }

    private fun checksum(b: ByteArray, off: Int, len: Int, initial: Int): Int {
        var sum = initial
        var i = off
        var remaining = len
        while (remaining > 1) {
            sum += u16(b, i)
            i += 2
            remaining -= 2
        }
        if (remaining == 1) sum += (b[i].toInt() and 0xFF) shl 8
        while (sum shr 16 != 0) sum = (sum and 0xFFFF) + (sum shr 16)
        return sum.inv() and 0xFFFF
    }
}
