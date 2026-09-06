import QtQuick
import QtTest
import ".." as Pulse

TestCase {
    name: "NetPulseWidgets"
    when: windowShown
    width: 760; height: 260

    Pulse.HistoryGraph { id: graph; width: 700; height: 139 }
    Pulse.NetChip { id: chip; width: 28; height: 25; compact: true; animate: false }

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
