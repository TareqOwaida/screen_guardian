package com.tareq.screen_guardian.dns

/**
 * Child-safety block rules evaluated on every DNS query.
 *
 * Layered approach:
 *  1. Upstream resolver is a family-filtered DNS (Cloudflare for Families
 *     1.1.1.3 – blocks malware, phishing and adult content) so the bulk of
 *     the categorisation is done by a continuously-updated provider.
 *  2. A built-in seed list of domains / keywords catches well-known adult,
 *     gambling, dating, gore and DNS-bypass (DoH/DoT) hosts even if the
 *     upstream misses them.
 *  3. Parent-supplied custom domains and IPs per profile.
 *  4. Answers whose A records resolve to a blocked IP are dropped, so blocked
 *     IPs cannot be reached through unknown domains.
 */
class BlockList(
    customDomains: Collection<String>,
    customIps: Collection<String>,
) {
    private val domains: Set<String> = (BUILT_IN_DOMAINS + customDomains.map { it.lowercase().trim().trimEnd('.') })
        .filter { it.isNotEmpty() }
        .toHashSet()
    private val ips: Set<String> = (BUILT_IN_IPS + customIps.map { it.trim() }).toHashSet()

    fun isDomainBlocked(rawHost: String): Boolean {
        val host = rawHost.lowercase().trimEnd('.')
        if (host.isEmpty()) return false
        // exact or parent-domain match
        var h = host
        while (true) {
            if (h in domains) return true
            val dot = h.indexOf('.')
            if (dot < 0) break
            h = h.substring(dot + 1)
        }
        // keyword match on any label
        for (kw in KEYWORDS) {
            if (host.contains(kw)) return true
        }
        return false
    }

    fun isIpBlocked(ip: String): Boolean = ip in ips

    companion object {
        /** Upstream family-safe resolvers (malware + adult filtering). */
        val UPSTREAM_DNS = listOf("1.1.1.3", "1.0.0.3", "185.228.168.168")

        private val KEYWORDS = listOf(
            "porn", "xxx", "hentai", "xvideos", "xnxx", "redtube", "youporn", "xhamster",
            "onlyfans", "sexcam", "camgirl", "livejasmin", "chaturbate", "stripchat",
            "escort", "casino", "gambling", "bet365", "pokerstars", "1xbet", "betway",
            "bestgore", "liveleak", "torrent", "thepiratebay",
        )

        private val BUILT_IN_DOMAINS = setOf(
            // adult
            "pornhub.com", "xvideos.com", "xnxx.com", "xhamster.com", "redtube.com", "youporn.com",
            "brazzers.com", "onlyfans.com", "chaturbate.com", "livejasmin.com", "stripchat.com",
            "spankbang.com", "tnaflix.com", "eporner.com", "motherless.com", "rule34.xxx",
            "nhentai.net", "hentaihaven.xxx", "fapello.com", "erome.com", "4chan.org", "8kun.top",
            // dating / hook-up
            "tinder.com", "badoo.com", "grindr.com", "adultfriendfinder.com", "ashleymadison.com",
            "omegle.com", "chatroulette.com", "ome.tv", "monkey.app",
            // gambling
            "bet365.com", "pokerstars.com", "888casino.com", "williamhill.com", "betway.com",
            "1xbet.com", "stake.com", "roobet.com", "draftkings.com", "fanduel.com",
            // violence / self-harm / drugs
            "bestgore.com", "liveleak.com", "theync.com", "kaotic.com", "documentingreality.com",
            "silkroad.onion", "dread.onion",
            // piracy / malware distribution
            "thepiratebay.org", "1337x.to", "rarbg.to", "yts.mx", "fmovies.to", "123movies.to",
            // proxies / VPN / DNS-bypass sites children use to escape filters
            "hide.me", "hidemyass.com", "kproxy.com", "proxysite.com", "croxyproxy.com",
            "4everproxy.com", "hola.org", "psiphon.ca", "ultrasurf.us",
            // DNS-over-HTTPS / DoT endpoints – block so apps fall back to system DNS (our filter)
            "dns.google", "cloudflare-dns.com", "one.one.one.one", "dns.quad9.net", "doh.opendns.com",
            "dns.adguard.com", "dns.nextdns.io", "doh.cleanbrowsing.org", "mozilla.cloudflare-dns.com",
            "dns.alidns.com", "doh.pub", "dns.sb", "doh.dns.sb", "dns.switch.ch", "use-application-dns.net",
        )

        private val BUILT_IN_IPS = setOf(
            // public resolvers that would bypass filtering if hard-coded by an app
            "8.8.8.8", "8.8.4.4", "1.1.1.1", "1.0.0.1", "9.9.9.9", "149.112.112.112",
            "208.67.222.222", "208.67.220.220", "94.140.14.14", "94.140.15.15",
        )
    }
}
