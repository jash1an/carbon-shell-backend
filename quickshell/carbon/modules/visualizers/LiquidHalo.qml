import QtQuick

/**
 * LiquidHalo:
 * Siri-style three-layer audio-reactive liquid rings centered on the nucleus.
 *
 * - 3 layered, translucent, closed liquid rings centered at (cx, cy)
 * - Layer 1 (bass): bands 0-5, m=(2,3), amp=16px, accent role 1 (teal)
 * - Layer 2 (mids): bands 6-20, m=(3,5), amp=13px, accent role 2 (blue)
 * - Layer 3 (treble): bands 21-47, m=(4,2), amp=11px, accent role 3 (purple)
 * - Fast attack (0.20), silky release (0.08), low-pass filter (0.10)
 * - Calms into completely motionless, perfect concentric circles when paused/idle
 * - Zero timers or animations run while idle (0% CPU at rest)
 */
Item {
    id: root

    /* ── Standard Common Visualizer Interface ── */
    property var bands: []
    property bool playing: false
    property color colorAccent1: "#00F0FF"
    property color colorAccent2: "#3B82F6"
    property color colorAccent3: "#A855F7"
    property bool reducedMotion: false

    implicitWidth: 140
    implicitHeight: 140

    /* ── Internal Filter States ── */
    property real stage1Bass: 0.0
    property real drawBass: 0.0
    property real stage1Mids: 0.0
    property real drawMids: 0.0
    property real stage1Treble: 0.0
    property real drawTreble: 0.0

    /* ── Harmonic Phase States (rad) ── */
    property real phase1_1: 0.0
    property real phase1_2: 0.0
    property real phase2_1: 0.0
    property real phase2_2: 0.0
    property real phase3_1: 0.0
    property real phase3_2: 0.0

    /* ── Animation Controller ── */
    property real speedFactor: 0.0
    property bool isAnimating: false
    property real lastFrameMs: 0.0

    onPlayingChanged: {
        if (playing) {
            isAnimating = true
        }
    }

    FrameAnimation {
        id: frameAnim
        running: root.isAnimating && root.visible
        onTriggered: root.updateFrame(frameTime)
    }

    function updateFrame(dtSec) {
        var dt = (dtSec && dtSec > 0.0) ? Math.min(32.0, Math.max(8.0, dtSec * 1000.0)) : 16.0

        /* 1. Extract Raw Energies from 48 Cava Bands */
        var rawBass = 0.0
        var rawMids = 0.0
        var rawTreble = 0.0

        if (root.playing && root.bands && root.bands.length >= 48) {
            // Bass: bands 0-5 averaged
            var bSum = 0.0
            for (var b = 0; b <= 5; b++) bSum += (root.bands[b] || 0.0)
            rawBass = Math.min(1.0, bSum / 6.0)

            // Mids: bands 6-20 averaged
            var mSum = 0.0
            for (var m = 6; m <= 20; m++) mSum += (root.bands[m] || 0.0)
            rawMids = Math.min(1.0, mSum / 15.0)

            // Treble: bands 21-47 averaged
            var tSum = 0.0
            for (var t = 21; t <= 47; t++) tSum += (root.bands[t] || 0.0)
            rawTreble = Math.min(1.0, tSum / 27.0)
        }

        /* 2. Smoothing: Fast Attack (0.2), Slower Release (0.08), Low-Pass (0.1) */
        // Bass
        if (rawBass > root.stage1Bass) {
            root.stage1Bass += (rawBass - root.stage1Bass) * 0.20
        } else {
            root.stage1Bass += (rawBass - root.stage1Bass) * 0.08
        }
        root.drawBass += (root.stage1Bass - root.drawBass) * 0.10

        // Mids
        if (rawMids > root.stage1Mids) {
            root.stage1Mids += (rawMids - root.stage1Mids) * 0.20
        } else {
            root.stage1Mids += (rawMids - root.stage1Mids) * 0.08
        }
        root.drawMids += (root.stage1Mids - root.drawMids) * 0.10

        // Treble
        if (rawTreble > root.stage1Treble) {
            root.stage1Treble += (rawTreble - root.stage1Treble) * 0.20
        } else {
            root.stage1Treble += (rawTreble - root.stage1Treble) * 0.08
        }
        root.drawTreble += (root.stage1Treble - root.drawTreble) * 0.10

        /* 3. Speed Factor Easing (eases to 0 on silence/pause or reduced motion) */
        if (root.playing && !root.reducedMotion) {
            root.speedFactor += (1.0 - root.speedFactor) * 0.10
        } else {
            root.speedFactor += (0.0 - root.speedFactor) * 0.08
        }

        /* 4. Phase Drift (continuous monotonic advance, never wraps, never snaps) */
        if (!root.reducedMotion && root.speedFactor > 0.0001) {
            // Layer 1 (bass, m=2, 3)
            root.phase1_1 += root.speedFactor * 0.70 * (1.0 + root.drawBass) * (dt / 1000.0)
            root.phase1_2 -= root.speedFactor * 0.50 * (1.0 + root.drawBass) * (dt / 1000.0)

            // Layer 2 (mids, m=3, 5)
            root.phase2_1 -= root.speedFactor * 0.80 * (1.0 + root.drawMids) * (dt / 1000.0)
            root.phase2_2 += root.speedFactor * 0.60 * (1.0 + root.drawMids) * (dt / 1000.0)

            // Layer 3 (treble, m=4, 2)
            root.phase3_1 += root.speedFactor * 0.90 * (1.0 + root.drawTreble) * (dt / 1000.0)
            root.phase3_2 -= root.speedFactor * 0.70 * (1.0 + root.drawTreble) * (dt / 1000.0)
        }

        /* 5. Silence / Pause Settling Check */
        if (!root.playing && root.drawBass < 0.0005 && root.drawMids < 0.0005 && root.drawTreble < 0.0005 && root.speedFactor < 0.0005) {
            root.stage1Bass = 0.0
            root.drawBass = 0.0
            root.stage1Mids = 0.0
            root.drawMids = 0.0
            root.stage1Treble = 0.0
            root.drawTreble = 0.0
            root.speedFactor = 0.0
            root.isAnimating = false // Fully halts frame timer at rest!
        }

        haloCanvas.requestPaint()
    }

    Component.onCompleted: {
        haloCanvas.requestPaint()
    }

    /* ── Render Canvas ── */
    Canvas {
        id: haloCanvas
        anchors.fill: parent
        renderTarget: Canvas.FramebufferObject
        renderStrategy: Canvas.Threaded

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()

            var cx = width / 2.0
            var cy = height / 2.0
            var bassOffset = root.drawBass * 6.0

            // Helper to sample and draw a smooth closed ring
            function drawClosedRing(baseRadius, amp, m1, m2, p1, p2, col) {
                var samples = 120
                var step = (2.0 * Math.PI) / samples

                ctx.beginPath()
                for (var i = 0; i <= samples; i++) {
                    var theta = i * step
                    var deformation = (amp > 0.0001)
                        ? amp * (0.6 * Math.sin(m1 * theta + p1) + 0.4 * Math.sin(m2 * theta + p2))
                        : 0.0
                    var r = baseRadius + deformation
                    var px = cx + r * Math.cos(theta)
                    var py = cy + r * Math.sin(theta)

                    if (i === 0) {
                        ctx.moveTo(px, py)
                    } else {
                        ctx.lineTo(px, py)
                    }
                }
                ctx.closePath()

                // Translucent liquid fill (alpha 0.21)
                ctx.fillStyle = Qt.rgba(col.r, col.g, col.b, 0.21)
                ctx.fill()

                // Crisp contour stroke (alpha 0.75, width 1.2px)
                ctx.strokeStyle = Qt.rgba(col.r, col.g, col.b, 0.75)
                ctx.lineWidth = 1.2
                ctx.stroke()
            }

            // Layer 3 (treble): base 36 + bassOffset + 3.0px, harmonics 4 & 2, amp 11px, Accent 3 (purple)
            drawClosedRing(
                36.0 + bassOffset + 3.0,
                root.drawTreble * 11.0,
                4, 2,
                root.phase3_1, root.phase3_2,
                root.colorAccent3
            )

            // Layer 2 (mids): base 36 + bassOffset + 1.5px, harmonics 3 & 5, amp 13px, Accent 2 (blue)
            drawClosedRing(
                36.0 + bassOffset + 1.5,
                root.drawMids * 13.0,
                3, 5,
                root.phase2_1, root.phase2_2,
                root.colorAccent2
            )

            // Layer 1 (bass): base 36 + bassOffset + 0.0px, harmonics 2 & 3, amp 16px, Accent 1 (teal)
            drawClosedRing(
                36.0 + bassOffset,
                root.drawBass * 16.0,
                2, 3,
                root.phase1_1, root.phase1_2,
                root.colorAccent1
            )
        }
    }
}
