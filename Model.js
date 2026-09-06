.pragma library
function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, Number(v) || 0)) }
function num(v) { var n = Number(v); return isFinite(n) ? n : 0 }
function has(v) { return v !== null && v !== undefined && isFinite(Number(v)) }
// Colour follows link health: dark red offline, yellow when struggling, green when the path is clean.
function ramp(percent) {
    var f = clamp(percent, 0, 100) / 100
    var a = f <= 0.5 ? [133, 13, 41] : [239, 204, 69]
    var b = f <= 0.5 ? [239, 204, 69] : [67, 242, 161]
    var t = f <= 0.5 ? f * 2 : (f - 0.5) * 2
    return Qt.rgba((a[0]+(b[0]-a[0])*t)/255, (a[1]+(b[1]-a[1])*t)/255, (a[2]+(b[2]-a[2])*t)/255, 1)
}
// Decimal units: network gear and speed tests quote MB/s and Mbit/s in powers of ten.
function rate(bps) {
    var n = Math.max(0, num(bps))
    if (n >= 1e9) return (n/1e9).toFixed(1)+' GB/s'
    if (n >= 1e6) return (n/1e6).toFixed(1)+' MB/s'
    if (n >= 1e3) return (n/1e3).toFixed(1)+' KB/s'
    return n.toFixed(0)+' B/s'
}
function shortRate(bps) {
    var n = Math.max(0, num(bps))
    if (n >= 1e9) return (n/1e9).toFixed(1)+'G'
    if (n >= 1e6) return (n/1e6).toFixed(1)+'M'
    if (n >= 1e3) return (n/1e3).toFixed(0)+'K'
    return n.toFixed(0)+'B'
}
function size(bytes) {
    var n = Math.max(0, num(bytes))
    if (n >= 1e12) return (n/1e12).toFixed(2)+' TB'
    if (n >= 1e9) return (n/1e9).toFixed(2)+' GB'
    if (n >= 1e6) return (n/1e6).toFixed(1)+' MB'
    if (n >= 1e3) return (n/1e3).toFixed(1)+' KB'
    return n.toFixed(0)+' B'
}
function mbit(v) {
    if (!has(v) || Number(v) <= 0) return '—'
    var n = Number(v)
    return n >= 1000 ? (n/1000).toFixed(n % 1000 === 0 ? 0 : 1)+' Gbit/s' : n.toFixed(0)+' Mbit/s'
}
// null = no sample yet, negative = probe timed out.
function ms(v) {
    if (!has(v)) return '—'
    var n = Number(v)
    if (n < 0) return 'timeout'
    return (n < 10 ? n.toFixed(1) : n.toFixed(0))+' ms'
}
function dbm(v) { return has(v) ? Math.round(Number(v))+' dBm' : '—' }
function pct(v) { return has(v) ? Number(v).toFixed(1)+'%' : '—' }
function whole(v) { return has(v) ? Math.round(Number(v))+'%' : '—' }
function count(v) {
    var n = num(v)
    return n >= 1e6 ? (n/1e6).toFixed(1)+'M' : n >= 1e4 ? (n/1e3).toFixed(1)+'k' : n.toFixed(0)
}
function perSec(v) { return count(v)+'/s' }
function ago(seconds) {
    var s = Math.max(0, Math.floor(num(seconds)))
    if (s < 60) return s+'s'
    if (s < 3600) return Math.floor(s/60)+'m '+(s%60)+'s'
    if (s < 86400) return Math.floor(s/3600)+'h '+Math.floor(s%3600/60)+'m'
    return Math.floor(s/86400)+'d '+Math.floor(s%86400/3600)+'h'
}
function band(mhz) {
    var v = num(mhz)
    if (!v) return ''
    if (v >= 2400 && v < 2500) return '2.4 GHz'
    if (v >= 4900 && v < 5925) return '5 GHz'
    if (v >= 5925 && v < 7125) return '6 GHz'
    return (v/1000).toFixed(1)+' GHz'
}
// The address without its prefix length: what you actually paste elsewhere.
function bare(addr) { return String(addr || '').split('/')[0] }
function isAddress(value) { return /^[0-9a-fA-F:.]{3,45}$/.test(String(value || '').trim()) }
function security(text) {
    var s = String(text || '').trim()
    if (!s || s === 'Open') return 'Open'
    if (s.indexOf('802.1X') >= 0) return 'Enterprise'
    if (s.indexOf('OWE') >= 0) return 'Enhanced open'
    if (s.indexOf('WPA3') >= 0) return 'WPA3'
    if (s.indexOf('WPA2') >= 0) return 'WPA2'
    if (s.indexOf('WPA1') >= 0 || s.indexOf('WPA') >= 0) return 'WPA'
    return s
}
function kindName(kind) {
    return {wifi: 'Wi-Fi', ethernet: 'Ethernet', tunnel: 'Tunnel', bridge: 'Bridge', loopback: 'Loopback', virtual: 'Virtual'}[kind] || 'Link'
}
// A single 0–100 score the chip colour follows. Offline is red; a captive
// portal or limited connectivity caps at yellow; latency, loss and a weak
// radio each take headroom away.
function health(m) {
    if (!m || !m.warm) return 50
    if (!m.online) return 0
    var h = 100
    var c = m.connectivity || 'unknown'
    if (c === 'portal' || c === 'limited' || c === 'none') h = Math.min(h, 40)
    var p = m.ping || {}
    if (has(p.internet)) {
        if (Number(p.internet) < 0) h -= 55
        else if (Number(p.internet) > 20) h -= Math.min(40, (Number(p.internet)-20)/180*40)
    }
    h -= Math.min(40, num(p.loss)*0.8)
    if (m.wifi && m.wifi.ssid && has(m.wifi.quality) && Number(m.wifi.quality) < 60) h -= (60-Number(m.wifi.quality))*1.2
    return clamp(h, 0, 100)
}
function healthLabel(m) {
    if (!m || !m.warm) return 'WAITING FOR TELEMETRY'
    if (!m.online) return 'NO ROUTE TO THE INTERNET'
    var c = m.connectivity || 'unknown'
    if (c === 'portal') return 'CAPTIVE PORTAL AHEAD'
    if (c === 'limited') return 'LIMITED CONNECTIVITY'
    if (c === 'none') return 'LINK UP · NO INTERNET'
    var p = m.ping || {}
    if (has(p.internet) && Number(p.internet) < 0) return 'INTERNET NOT ANSWERING'
    if (num(p.loss) >= 10) return 'PACKETS ARE GOING MISSING'
    if (has(p.internet) && Number(p.internet) > 120) return 'SLOW PATH TO THE INTERNET'
    if (m.wifi && m.wifi.ssid && has(m.wifi.quality) && Number(m.wifi.quality) < 40) return 'WEAK RADIO SIGNAL'
    return 'CLEAR PATH TO THE INTERNET'
}
function isWifi(m) { return !!(m && m.iface && m.iface.kind === 'wifi' && m.wifi && m.wifi.ssid) }
function readout(m, mode) {
    if (!m || !m.warm) return '—'
    if (!m.online) return 'offline'
    if (mode === 1) return isWifi(m) ? dbm(m.wifi.signal) : mbit(m.iface.speed)
    if (mode === 2) return ms(has(m.ping.internet) ? m.ping.internet : m.ping.gateway)
    if (mode === 3) return isWifi(m) ? m.wifi.ssid : (m.iface.connection || m.iface.name || '—')
    if (mode === 4) return (m.iface.addrs4 && m.iface.addrs4.length ? m.iface.addrs4[0] : m.iface.addrs6 && m.iface.addrs6.length ? m.iface.addrs6[0] : 'no address').split('/')[0]
    return '↓ '+rate(m.rates ? m.rates.rx : 0)
}
function modeTag(m, mode) {
    if (!m || !m.warm || !m.online) return 'NETWORK'
    if (mode === 1) return isWifi(m) ? whole(m.wifi.quality)+' SIGNAL' : 'LINK SPEED'
    if (mode === 2) return has(m.ping.internet) ? 'INTERNET' : 'GATEWAY'
    if (mode === 3) return isWifi(m) ? (m.wifi.band || band(m.wifi.freq))+(m.wifi.channel ? ' · CH '+m.wifi.channel : '') : kindName(m.iface.kind).toUpperCase()
    if (mode === 4) return String(m.iface.name || '').toUpperCase()
    return '↑ '+rate(m.rates ? m.rates.tx : 0)
}
function modeName(mode) { return ['Throughput', 'Signal / link speed', 'Latency', 'Network name', 'IP address'][mode] || 'Throughput' }
// Axis ceiling for the history graph: 1–2–5 steps, never below 10 KB/s so a quiet link is not magnified into noise.
function niceMax(v) {
    var n = Math.max(1e4, num(v)*1.15)
    var p = Math.pow(10, Math.floor(Math.log(n)/Math.LN10))
    var f = n/p
    return (f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10)*p
}
function niceMs(v) {
    var n = Math.max(20, num(v)*1.15)
    var p = Math.pow(10, Math.floor(Math.log(n)/Math.LN10))
    var f = n/p
    return (f <= 1 ? 1 : f <= 2 ? 2 : f <= 5 ? 5 : 10)*p
}
