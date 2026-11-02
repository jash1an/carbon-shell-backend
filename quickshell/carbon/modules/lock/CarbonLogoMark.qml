import QtQuick
import QtQuick.Shapes
import "../../Singletons"

/**
 * CarbonLogoMark.qml
 *
 * Vector implementation of the animated Carbon brand mark:
 * - High-precision GPU curve rendering with subpixel antialiasing
 * - Central luminous nucleus with soft radial glow and dual-ring breathing halo
 * - Rotating dual-spiral orbit with 54s base cycle
 * - Outward drawing intro sequence for spirals & staggered tail pieces
 * - 8s breathing/shimmer/drift cycle for tail segments with local centroid scaling
 * - Periodic coral expanding ping rings and luminous glows on lobes
 * - Interactive typing bump reaction (scale pulse, center ring, rotation speedup)
 * - Wrong-password reaction (coral glow pulse, 10x rotation boost)
 * - Fluid exit dissolve sequence on unlock
 */
Item {
    id: logoRoot

    implicitWidth: 200
    implicitHeight: 200

    property string phase: LockTransition.phase
    property real t: LockTransition.t
    property real u: LockTransition.u
    property bool isExiting: false

    // Timing helper: easing
    function easeOutCubic(p) {
        var x = Math.max(0.0, Math.min(1.0, p))
        return 1.0 - Math.pow(1.0 - x, 3.0)
    }

    function easeInOutCubic(p) {
        var x = Math.max(0.0, Math.min(1.0, p))
        return x < 0.5 ? 4.0 * x * x * x : 1.0 - Math.pow(-2.0 * x + 2.0, 3.0) / 2.0
    }

    function easeOutBack(p) {
        var c1 = 1.70158
        var c3 = c1 + 1.0
        var x = Math.max(0.0, Math.min(1.0, p))
        return 1.0 + c3 * Math.pow(x - 1.0, 3.0) + c1 * Math.pow(x - 1.0, 2.0)
    }

    /* ── Continuous Animation Driver ─────────────────────────────────────── */
    property real runningTime: 0.0
    property real orbitRotation: 0.0
    property real currentOrbitRate: 1.0
    property real targetOrbitRate: 1.0
    property real bumpScale: 1.0
    property real coralGlowOpacity: 0.0

    FrameAnimation {
        id: logoDriver
        running: logoRoot.visible && logoRoot.opacity > 0.001
        onTriggered: {
            var dt = frameTime * 1000.0
            logoRoot.runningTime += dt

            // Smooth orbit rate easing
            logoRoot.currentOrbitRate += (logoRoot.targetOrbitRate - logoRoot.currentOrbitRate) * Math.min(1.0, frameTime * 7.0)

            // Orbit rotation: 360 deg in 54000ms = 0.006667 deg/ms * rate
            var degStep = (360.0 / 54000.0) * dt * logoRoot.currentOrbitRate
            logoRoot.orbitRotation = (logoRoot.orbitRotation + degStep) % 360.0
        }
    }

    /* ── Interactive Trigger Functions ───────────────────────────────────── */
    function bump() {
        if (LockTransition.reducedMotion) return
        bumpAnim.restart()
        kringAnim.restart()
        logoRoot.targetOrbitRate = 7.0
        relaxTimer.restart()
    }

    function wrong() {
        if (LockTransition.reducedMotion) return
        wrongGlowAnim.restart()
        logoRoot.targetOrbitRate = 10.0
        relaxTimer.interval = 520
        relaxTimer.restart()
    }

    function triggerExit() {
        logoRoot.isExiting = true
    }

    function reset() {
        logoRoot.isExiting = false
        logoRoot.targetOrbitRate = 1.0
        logoRoot.currentOrbitRate = 1.0
        logoRoot.bumpScale = 1.0
        logoRoot.coralGlowOpacity = 0.0
    }

    Connections {
        target: LockTransition
        function onPhaseChanged() {
            if (LockTransition.phase === "idle") {
                logoRoot.reset()
            }
        }
    }

    Timer {
        id: relaxTimer
        interval: 700
        repeat: false
        onTriggered: {
            logoRoot.targetOrbitRate = 1.0
        }
    }

    SequentialAnimation {
        id: bumpAnim
        NumberAnimation {
            target: logoRoot
            property: "bumpScale"
            from: 1.0; to: 1.04
            duration: 160
            easing.type: Easing.OutBack
            easing.overshoot: 1.56
        }
        NumberAnimation {
            target: logoRoot
            property: "bumpScale"
            from: 1.04; to: 1.0
            duration: 160
            easing.type: Easing.OutCubic
        }
    }

    SequentialAnimation {
        id: wrongGlowAnim
        NumberAnimation {
            target: logoRoot
            property: "coralGlowOpacity"
            from: 0.0; to: 0.90
            duration: 250
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: logoRoot
            property: "coralGlowOpacity"
            from: 0.90; to: 0.0
            duration: 650
            easing.type: Easing.OutCubic
        }
    }

    /* ── Intro & Exit State Progression ──────────────────────────────────── */
    // Lock-in: logo appears at t = 180ms. Logo intro clock (ms from appearance, accelerated 1.45x):
    readonly property real introMs: {
        if (phase === "locked") return 5000.0
        if (phase === "locking") return Math.max(0.0, (t - 180.0) * 1.45)
        return 0.0
    }

    // Unlock-out: logo exit starts at u = 160ms. Exit clock (ms from start):
    readonly property real exitMs: {
        if (phase === "unlocking" || phase === "post_unlock") return Math.max(0.0, u - 160.0)
        if (logoRoot.isExiting) return 500.0
        return 0.0
    }
    readonly property bool exiting: ((phase === "unlocking" || phase === "post_unlock") && u >= 160.0) || logoRoot.isExiting

    /* ── Breathing Rhythm for Core and Halo (4.2s alternating) ───────────── */
    readonly property real breathePhase: (logoRoot.runningTime % 4200.0) / 4200.0
    readonly property real breatheScale: 1.0 + 0.045 * Math.sin(breathePhase * 2.0 * Math.PI)
    readonly property real breatheHaloScale: 1.0 + 0.060 * Math.sin((breathePhase + 0.25) * 2.0 * Math.PI)
    readonly property real breatheHaloOpacity: 0.55 + 0.45 * Math.cos(breathePhase * 2.0 * Math.PI)

    // Master Scale Transform
    scale: logoRoot.bumpScale

    /* ── A. Coral Glow behind logo (Wrong password reaction) ─────────────── */
    Rectangle {
        id: eglow
        anchors.centerIn: parent
        width: 250
        height: 250
        radius: 125
        color: "transparent"
        border.color: "#f2705f"
        border.width: 40
        opacity: logoRoot.coralGlowOpacity * 0.45
        visible: opacity > 0.005
        antialiasing: true
        smooth: true
    }

    /* ── B. Center White Shock Ring on Keypress (kring) ──────────────────── */
    Rectangle {
        id: kring
        anchors.centerIn: parent
        width: 70
        height: 70
        radius: 35
        color: "transparent"
        border.color: Qt.rgba(1, 1, 1, 0.70)
        border.width: 1.5
        property real kringScale: 0.6
        property real kringAlpha: 0.0
        scale: kringScale
        opacity: kringAlpha
        antialiasing: true
        smooth: true

        ParallelAnimation {
            id: kringAnim
            NumberAnimation {
                target: kring
                property: "kringScale"
                from: 0.6; to: 2.6
                duration: 900
                easing.type: Easing.OutCubic
            }
            NumberAnimation {
                target: kring
                property: "kringAlpha"
                from: 0.55; to: 0.0
                duration: 900
                easing.type: Easing.OutCubic
            }
        }
    }

    /* ── C. Outer Halo ───────────────────────────────────────────────────── */
    Item {
        id: haloGroup
        anchors.centerIn: parent
        width: 64
        height: 64

        readonly property real haloIntroP: Math.max(0.0, Math.min(1.0, (logoRoot.introMs - 155.0) / 620.0))
        readonly property real haloIntroScale: 1.55 - 0.55 * logoRoot.easeOutCubic(haloIntroP)
        readonly property real haloExitP: Math.max(0.0, Math.min(1.0, (logoRoot.exitMs - 350.0) / 500.0))

        scale: logoRoot.exiting ? Math.max(0.0, 1.0 - haloExitP) : (logoRoot.introMs < 155.0 ? 0.0 : haloIntroScale * logoRoot.breatheHaloScale)
        opacity: logoRoot.exiting ? Math.max(0.0, 1.0 - haloExitP) : (logoRoot.introMs < 155.0 ? 0.0 : Math.min(1.0, haloIntroP * 1.5) * logoRoot.breatheHaloOpacity)

        // Filled disk r=32
        Rectangle {
            anchors.centerIn: parent
            width: 64
            height: 64
            radius: 32
            color: "#f4f6f5"
            opacity: 0.07
            antialiasing: true
            smooth: true
        }

        // Thin stroke ring r=29, stroke 3
        Rectangle {
            anchors.centerIn: parent
            width: 58
            height: 58
            radius: 29
            color: "transparent"
            border.color: "#f4f6f5"
            border.width: 3
            opacity: 0.26
            antialiasing: true
            smooth: true
        }
    }

    /* ── D. Central Nucleus ──────────────────────────────────────────────── */
    // Soft radial emissive glow
    Rectangle {
        anchors.centerIn: nucleusCore
        width: 52
        height: 52
        radius: 26
        color: Qt.rgba(0.96, 0.96, 0.96, 0.22)
        scale: nucleusCore.scale
        opacity: nucleusCore.opacity
        antialiasing: true
        smooth: true
    }

    Rectangle {
        id: nucleusCore
        anchors.centerIn: parent
        width: 40
        height: 40
        radius: 20
        color: "#f4f6f5"
        antialiasing: true
        smooth: true

        readonly property real nucPopP: Math.max(0.0, Math.min(1.0, logoRoot.introMs / 589.0))
        readonly property real nucExitP: Math.max(0.0, Math.min(1.0, (logoRoot.exitMs - 1140.0) / 420.0))

        scale: {
            if (logoRoot.exiting) {
                if (logoRoot.exitMs < 1140.0) return 1.0
                return Math.max(0.0, 1.0 - logoRoot.easeOutCubic(nucExitP))
            }
            if (logoRoot.introMs < 10.0) return 0.0
            return (0.35 + 0.65 * logoRoot.easeOutBack(nucPopP)) * logoRoot.breatheScale
        }
        opacity: {
            if (logoRoot.exiting) {
                if (logoRoot.exitMs < 1140.0) return 1.0
                return Math.max(0.0, 1.0 - logoRoot.easeOutCubic(nucExitP))
            }
            return logoRoot.introMs < 10.0 ? 0.0 : Math.min(1.0, nucPopP * 1.8)
        }
    }

    /* ── E. Rotating Orbit Group (Spirals, Tails, Coral Lobes) ───────────── */
    Item {
        id: orbitGroup
        anchors.centerIn: parent
        width: 200
        height: 200
        rotation: logoRoot.orbitRotation
        transformOrigin: Item.Center

        /* ── 1. Spiral 2 Body (Faint Twin) ── */
        Shape {
            anchors.fill: parent
            antialiasing: true
            smooth: true
            preferredRendererType: Shape.CurveRenderer

            readonly property real s2DrawP: Math.max(0.0, Math.min(1.0, (logoRoot.introMs - 155.0) / 837.0))
            readonly property real s2ExitP: Math.max(0.0, Math.min(1.0, logoRoot.exitMs / 750.0))

            readonly property real drawFraction: {
                if (logoRoot.exiting) return Math.max(0.0, 1.0 - logoRoot.easeInOutCubic(s2ExitP))
                if (logoRoot.introMs < 155.0) return 0.0
                return logoRoot.easeInOutCubic(s2DrawP)
            }

            opacity: drawFraction > 0.01 ? 0.42 : 0.0

            ShapePath {
                strokeColor: "#f4f6f5"
                strokeWidth: 5.4
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                dashPattern: parent.drawFraction < 0.999 ? [175, 175] : []
                dashOffset: 175.0 * (1.0 - parent.drawFraction)

                PathSvg {
                    path: "M100.0 138.0 L98.1 138.2 L96.2 138.3 L94.2 138.3 L92.3 138.2 L90.3 138.0 L88.4 137.7 L86.4 137.3 L84.5 136.8 L82.6 136.2 L80.7 135.5 L78.8 134.7 L76.9 133.8 L75.1 132.8 L73.3 131.8 L71.6 130.6 L69.9 129.3 L68.3 128.0 L66.8 126.5 L65.3 125.0 L63.9 123.3 L62.5 121.6 L61.2 119.9 L60.0 118.0 L59.0 116.1 L57.9 114.1 L57.0 112.1 L56.2 110.0 L55.5 107.8 L54.9 105.6 L54.4 103.4 L54.0 101.1 L53.8 98.8 L53.6 96.5 L53.6 94.2 L53.7 91.8 L53.9 89.5 L54.2 87.1 L54.6 84.8 L55.2 82.4 L55.9 80.1 L56.7 77.8 L57.6 75.5 L58.6 73.3 L59.8 71.1 L61.1 69.0 L62.5 66.9 L64.0 64.8 L65.6 62.9 L67.3 61.0 L69.1 59.2 L71.0 57.5 L73.0 55.9 L75.1 54.3 L77.3 52.9 L79.6 51.6 L81.9 50.3 L84.3 49.2 L86.8 48.3 L89.4 47.4 L92.0 46.6 L94.6 46.0 L97.3 45.6 L100.0 45.2 L102.7 45.0 L105.5 44.9 L108.3 45.0 L111.1 45.2 L113.9 45.5 L116.6 46.0 L119.4 46.7"
                }
            }
        }

        /* ── 2. Spiral 1 Body (Strong Master) ── */
        Shape {
            anchors.fill: parent
            antialiasing: true
            smooth: true
            preferredRendererType: Shape.CurveRenderer

            readonly property real s1DrawP: Math.max(0.0, Math.min(1.0, (logoRoot.introMs - 435.0) / 837.0))
            readonly property real s1ExitP: Math.max(0.0, Math.min(1.0, logoRoot.exitMs / 750.0))

            readonly property real drawFraction: {
                if (logoRoot.exiting) return Math.max(0.0, 1.0 - logoRoot.easeInOutCubic(s1ExitP))
                if (logoRoot.introMs < 435.0) return 0.0
                return logoRoot.easeInOutCubic(s1DrawP)
            }

            opacity: drawFraction > 0.01 ? 1.0 : 0.0

            ShapePath {
                strokeColor: "#f4f6f5"
                strokeWidth: 6.4
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                dashPattern: parent.drawFraction < 0.999 ? [175, 175] : []
                dashOffset: 175.0 * (1.0 - parent.drawFraction)

                PathSvg {
                    path: "M100.0 62.0 L101.9 61.8 L103.8 61.7 L105.8 61.7 L107.7 61.8 L109.7 62.0 L111.6 62.3 L113.6 62.7 L115.5 63.2 L117.4 63.8 L119.3 64.5 L121.2 65.3 L123.1 66.2 L124.9 67.2 L126.7 68.2 L128.4 69.4 L130.1 70.7 L131.7 72.0 L133.2 73.5 L134.7 75.0 L136.1 76.7 L137.5 78.4 L138.8 80.1 L140.0 82.0 L141.0 83.9 L142.1 85.9 L143.0 87.9 L143.8 90.0 L144.5 92.2 L145.1 94.4 L145.6 96.6 L146.0 98.9 L146.2 101.2 L146.4 103.5 L146.4 105.8 L146.3 108.2 L146.1 110.5 L145.8 112.9 L145.4 115.2 L144.8 117.6 L144.1 119.9 L143.3 122.2 L142.4 124.5 L141.4 126.7 L140.2 128.9 L138.9 131.0 L137.5 133.1 L136.0 135.2 L134.4 137.1 L132.7 139.0 L130.9 140.8 L129.0 142.5 L127.0 144.1 L124.9 145.7 L122.7 147.1 L120.4 148.4 L118.1 149.7 L115.7 150.8 L113.2 151.7 L110.6 152.6 L108.0 153.4 L105.4 154.0 L102.7 154.4 L100.0 154.8 L97.3 155.0 L94.5 155.1 L91.7 155.0 L88.9 154.8 L86.1 154.5 L83.4 154.0 L80.6 153.3"
                }
            }
        }

    }
}
