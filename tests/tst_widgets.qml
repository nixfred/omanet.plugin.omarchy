import QtQuick
import QtTest
import ".." as Pulse
import "../Model.js" as Model

TestCase {
    name: "NetPulseWidgets"
    when: windowShown
    // The chip only paints while it is actually on screen, so the case itself
    // has to be shown or nothing under test ever repaints.
    visible: true
    width: 760; height: 260

    Pulse.HistoryGraph { id: graph; width: 700; height: 139 }
    Pulse.NetChip { id: chip; width: 28; height: 25; compact: true; animate: false }
    Pulse.UsageGraph { id: usage; width: 700; height: 160 }

    // The bar readout, reproduced exactly as Panel.qml lays it out.
    Text {
        id: probe; visible: false; font.pixelSize: 12; font.bold: true
        width: Math.max(implicitWidth, probeFloor.implicitWidth)
    }
    Text { id: probeFloor; visible: false; font: probe.font; text: Model.widestReadout(probeSnapshot, probeMode) }
    property int probeMode: 0
    property var probeSnapshot: ({warm: true, online: true, iface: {kind: 'wifi', name: 'wlp2s0'},
                                  wifi: {ssid: 'ILoveMyWifi'}, ping: {}, rates: {rx: 0, tx: 0}})
    function snap(fields) {
        var m = {warm: true, online: true, iface: {kind: 'wifi', name: 'wlp2s0', speed: null},
                 wifi: {ssid: 'ILoveMyWifi'}, ping: {}, rates: {rx: 0, tx: 0}}
        for (var key in fields) m[key] = fields[key]
        return m
    }

    // [ts, rxAvg, rxPeak, txAvg, latency, signal, count, boot]
    function test_hover_survives_an_emptied_history() {
        failOnWarning(/.*/)
        graph.historyData = {points: [[100, 4000, 9000, 1200, 18.5, 74, 1, 'boot']], seconds: 3600, now: 100, bucket: 15, peakRx: 9000, peakTx: 1200, peakLatency: 18.5}
        graph.hoverIndex = 0
        compare(graph.hoverPoint[1], 4000)
        graph.historyData = {points: [], seconds: 3600, now: 101, bucket: 15, peakRx: 0, peakTx: 0, peakLatency: 0}
        compare(graph.hoverPoint, null)
        graph.hoverIndex = 0
        compare(graph.hoverPoint, null)
        wait(30)
    }

    function test_missing_latency_and_signal_do_not_break_the_trace() {
        failOnWarning(/.*/)
        graph.historyData = {points: [
            [100, 4000, 9000, 1200, null, null, 1, 'a'],
            [115, 5000, 9000, 1300, 20, 60, 1, 'a'],
            [900, 5000, 9000, 1300, 20, 60, 1, 'b']
        ], seconds: 3600, now: 900, bucket: 15, peakRx: 9000, peakTx: 1300, peakLatency: 20}
        wait(30)
        verify(graph.ceiling >= 9000)
        verify(graph.msCeiling >= 20)
    }

    function test_phase_advances_only_while_animated_and_visible() {
        failOnWarning(/.*/)
        chip.animate = false
        chip.phase = 0
        wait(250)
        compare(chip.phase, 0, 'a still chip must not tick')
        chip.animate = true
        tryVerify(function() { return chip.phase > 0 }, 2000)
        chip.visible = false
        var frozen = chip.phase
        wait(300)
        compare(chip.phase, frozen, 'an off-screen chip must not tick')
        chip.visible = true
        tryVerify(function() { return chip.phase > frozen }, 2000)
        chip.animate = false
    }

    // [bucketStart, rxBytes, txBytes]
    function test_usage_bars_survive_an_emptied_range() {
        failOnWarning(/.*/)
        usage.usageData = {points: [[3600, 4e6, 1e6], [7200, 8e6, 2e6]], seconds: 7200, bucket: 3600, start: 3600, now: 10800, peak: 1e7}
        usage.hoverIndex = 1
        compare(usage.hoverPoint[1], 8e6)
        verify(usage.ceiling >= 1e7)
        usage.usageData = {points: [], seconds: 7200, bucket: 3600, start: 3600, now: 10800, peak: 0}
        compare(usage.hoverPoint, null)
        usage.hoverIndex = 0
        compare(usage.hoverPoint, null)
        wait(30)
    }

    // A range with nothing in it still has to lay out an axis rather than
    // divide by a zero span, a zero bucket or a zero ceiling.
    function test_an_empty_usage_range_still_paints() {
        failOnWarning(/.*/)
        usage.usageData = {points: [], seconds: 0, bucket: 0, start: 0, now: 0, peak: 0}
        wait(30)
        verify(usage.span >= 1)
        verify(usage.ceiling > 0)
        verify(usage.barWidth() >= 1)
    }

    // One bucket as wide as the whole window must still be a visible bar.
    function test_a_single_bucket_fills_the_plot() {
        failOnWarning(/.*/)
        usage.usageData = {points: [[0, 5e6, 5e5]], seconds: 3600, bucket: 3600, start: 0, now: 3600, peak: 5.5e6}
        wait(30)
        verify(usage.barWidth() > usage.plotWidth()*0.9)
    }

    // The label has to name the bucket at every width the collector emits.
    function test_bucket_labels_follow_the_bucket_width() {
        failOnWarning(/.*/)
        var widths = [60, 3600, 21600, 86400, 604800]
        for (var i = 0; i < widths.length; i++) {
            usage.usageData = {points: [], seconds: widths[i]*4, bucket: widths[i], start: 1757000000, now: 1757000000 + widths[i]*4, peak: 0}
            verify(usage.bucketLabel(1757000000).length > 0, 'bucket ' + widths[i] + ' has no label')
            // The axis names an instant, never a span: a dash there reads as
            // the whole window rather than as where it starts.
            var axis = usage.axisLabel(1757000000)
            verify(axis.length > 0, 'bucket ' + widths[i] + ' has no axis label')
            compare(axis.indexOf('–'), -1, 'axis label for bucket ' + widths[i] + ' is a range')
        }
        wait(30)
    }

    // A widget that changes width every two seconds re-lays out its whole bar
    // section, and on a full bar it ends up drawn over its neighbour. Whatever
    // the link is doing, the readout must occupy exactly one width.
    function test_the_bar_readout_holds_one_width_in_every_changing_mode() {
        failOnWarning(/.*/)
        var cases = {
            0: [0, 512, 9900, 34800, 254200, 999900, 1200000, 48000000, 999900000].map(function(r) {
                   return snap({rates: {rx: r, tx: r}}) }),
            1: [-31, -46, -78, -100].map(function(d) { return snap({wifi: {ssid: 'ILoveMyWifi', signal: d, quality: 83}}) }),
            2: [0.4, 9.9, 11.2, 120, 999, 1500, -1].map(function(l) { return snap({ping: {internet: l}}) })
        }
        for (var mode in cases) {
            probeMode = Number(mode)
            var seen = {}, count = 0
            for (var i = 0; i < cases[mode].length; i++) {
                probe.text = Model.readout(cases[mode][i], Number(mode))
                verify(probe.implicitWidth <= probe.width, probe.text + ' is clipped by its reservation')
                if (seen[probe.width] === undefined) { seen[probe.width] = true; count++ }
            }
            compare(count, 1, 'mode ' + mode + ' took more than one width')
        }
        wait(30)
    }

    function test_every_chip_kind_paints() {
        failOnWarning(/.*/)
        var kinds = ['wifi', 'ethernet', 'offline']
        for (var i = 0; i < kinds.length; i++) {
            chip.kind = kinds[i]
            chip.level = i / 2
            chip.activity = 1 - i / 2
            wait(30)
        }
        chip.compact = false
        chip.width = 160; chip.height = 160
        chip.animate = true
        chip.kind = 'wifi'
        wait(60)
        chip.animate = false
        wait(30)
    }
}
