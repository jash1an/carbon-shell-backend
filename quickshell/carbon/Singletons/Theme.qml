pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Carbon Theme Engine — Powered by Caelestia's Material Design 3 (M3) System.
 *
 * Reads dynamic color tokens directly from Caelestia (~/.local/state/caelestia/scheme.json)
 * and falls back to ~/.config/hypr/theme.json.
 * Updates live across all components in real time without restarting Quickshell.
 */
Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") || "/home/" + (Quickshell.env("USER") || "user")
    readonly property string configDir: Quickshell.env("CARBON_CONFIG_DIR") || (root.home + "/.config/carbon")
    readonly property string caelestiaSchemePath: root.home + "/.local/state/caelestia/scheme.json"
    readonly property string fallbackThemePath: root.configDir + "/theme.json"
    readonly property string barPosPath: root.configDir + "/carbon-bar-position.json"
    readonly property string fontsConfigPath: root.configDir + "/carbon-fonts.json"

    property real shellOpacity: 0.85
    property string customFont: ""
    property string customFontMono: ""
    property real customFontScale: 1.0

    /* ── Connectivity Orbit Picker Tokens ── */
    readonly property int wifiOrbitBase: 118
    readonly property int wifiOrbitFactor: 52
    readonly property int guideRingInner: 70
    readonly property int guideRingOuter: 105
    readonly property int btInnerRadius: 66
    readonly property int btOuterRadius: 112
    readonly property int connectivityScanInterval: 8000
    readonly property bool reducedMotion: false
    readonly property bool bluetoothHeadsetDefaultAudio: false

    /* ── Caelestia Material 3 Expressive Animation Tokens ── */
    readonly property var animCurves: ({
        expressiveFastSpatial: [0.42, 1.67, 0.21, 0.9, 1.0, 1.0],
        expressiveDefaultSpatial: [0.38, 1.21, 0.22, 1.0, 1.0, 1.0],
        expressiveSlowSpatial: [0.39, 1.29, 0.35, 0.98, 1.0, 1.0],
        expressiveFastEffects: [0.31, 0.94, 0.34, 1.0, 1.0, 1.0],
        expressiveDefaultEffects: [0.34, 0.8, 0.34, 1.0, 1.0, 1.0],
        standardAccel: [0.3, 0.0, 0.8, 0.15, 1.0, 1.0],
        emphasizedDecel: [0.05, 0.7, 0.1, 1.0, 1.0, 1.0]
    })
    readonly property var animDurations: ({
        openPopup: 380,
        closePopup: 200,
        fastSpatial: 350,
        defaultSpatial: 500,
        slowSpatial: 650,
        fastEffects: 150,
        defaultEffects: 200
    })

    FileView {
        id: barPosFile
        path: root.barPosPath
        watchChanges: true
        blockLoading: true
        printErrors: false
        onFileChanged: root.reloadShellOpacity()
        onLoaded: root.reloadShellOpacity()
    }

    function reloadShellOpacity() {
        try {
            var txt = barPosFile.text().trim()
            if (txt.length > 0) {
                var d = JSON.parse(txt)
                if (d.shellOpacity !== undefined) {
                    root.shellOpacity = Math.max(0.10, Math.min(1.0, parseFloat(d.shellOpacity) || 0.85))
                }
            }
        } catch (e) {}
        root.reload()
    }

    FileView {
        id: fontsFile
        path: root.fontsConfigPath
        watchChanges: true
        blockLoading: true
        printErrors: false
        onFileChanged: root.reloadFonts()
        onLoaded: root.reloadFonts()
    }

    function reloadFonts() {
        try {
            var txt = fontsFile.text().trim()
            if (txt.length > 0) {
                var d = JSON.parse(txt)
                if (d.interface_font && String(d.interface_font).length > 0) {
                    root.customFont = String(d.interface_font) + ", Rubik, Google Sans Flex, sans-serif"
                }
                if (d.monospace_font && String(d.monospace_font).length > 0) {
                    root.customFontMono = String(d.monospace_font) + ", monospace"
                }
                if (d.scaling_factor !== undefined) {
                    root.customFontScale = Math.max(0.5, Math.min(2.0, parseFloat(d.scaling_factor) || 1.0))
                }
            }
        } catch (e) {}
    }

    FileView {
        id: caelestiaFile
        path: root.caelestiaSchemePath
        watchChanges: true
        blockLoading: true
        printErrors: false
        onFileChanged: root.reload()
        onLoaded: root.reload()
    }

    FileView {
        id: fallbackFile
        path: root.fallbackThemePath
        watchChanges: true
        blockLoading: true
        printErrors: false
        onFileChanged: root.reload()
        onLoaded: root.reload()
    }

    property var palette: ({})
    property string schemeName: "caelestia"

    /* Helper to normalize color hex codes (with leading '#') */
    function col(val, fallback) {
        if (!val || val === undefined) return fallback
        var s = String(val).trim()
        if (s.length === 0) return fallback
        if (s.startsWith("#")) return s
        return "#" + s
    }

    function lum(c) {
        if (!c) return 0
        try {
            var qc = Qt.color(c)
            return 0.299 * qc.r + 0.587 * qc.g + 0.114 * qc.b
        } catch (e) {
            return 0
        }
    }

    function reload() {
        try {
            caelestiaFile.reload()
            var txt = caelestiaFile.text().trim()
            var parsed = null

            if (txt.length > 0) {
                try {
                    parsed = JSON.parse(txt)
                } catch (pe) {
                    parsed = null
                }
            }

            if (parsed && parsed.colours) {
                /* Loaded from Caelestia scheme.json */
                var c = parsed.colours
                root.schemeName = parsed.name || "caelestia"
                root.palette = c
                root.isDark = (parsed.mode !== "light")

                /* Material 3 Surface & Color Tokens */
                root.m3background = col(c.background, "#0e0e12")
                root.m3onBackground = col(c.onBackground, "#e6e4f0")
                root.m3surface = col(c.surface, "#0e0e12")
                root.m3surfaceDim = col(c.surfaceDim, "#0e0e12")
                root.m3surfaceBright = col(c.surfaceBright, "#2b2b34")
                root.m3surfaceContainerLowest = col(c.surfaceContainerLowest, "#000000")
                root.m3surfaceContainerLow = col(c.surfaceContainerLow, "#131318")
                root.m3surfaceContainer = col(c.surfaceContainer, "#191920")
                root.m3surfaceContainerHigh = col(c.surfaceContainerHigh, "#1f1f26")
                root.m3surfaceContainerHighest = col(c.surfaceContainerHighest, "#24252e")

                root.m3onSurface = col(c.onSurface, "#e6e4f0")
                root.m3surfaceVariant = col(c.surfaceVariant, "#24252e")
                root.m3onSurfaceVariant = col(c.onSurfaceVariant, "#abaab5")
                root.m3outline = col(c.outline, "#75747f")
                root.m3outlineVariant = col(c.outlineVariant, "#474750")

                root.m3primary = col(c.primary, "#c0c4ee")
                root.m3primaryDim = col(c.primaryDim, "#b2b6e0")
                root.m3onPrimary = col(c.onPrimary, "#393e61")
                root.m3primaryContainer = col(c.primaryContainer, "#4b5074")
                root.m3onPrimaryContainer = col(c.onPrimaryContainer, "#e0e1ff")

                root.m3secondary = col(c.secondary, "#c4c5dd")
                root.m3onSecondary = col(c.onSecondary, "#3d3f52")
                root.m3secondaryContainer = col(c.secondaryContainer, "#383a4d")
                root.m3onSecondaryContainer = col(c.onSecondaryContainer, "#bdbdd5")

                root.m3tertiary = col(c.tertiary, "#fbe3ff")
                root.m3onTertiary = col(c.onTertiary, "#684d73")
                root.m3tertiaryContainer = col(c.tertiaryContainer, "#f5d1ff")
                root.m3onTertiaryContainer = col(c.onTertiaryContainer, "#60446a")

                root.m3error = col(c.error, "#f97386")
                root.m3onError = col(c.onError, "#490013")
                root.m3errorContainer = col(c.errorContainer, "#871c34")

                root.m3success = col(c.success, "#B5CCBA")
                root.m3onSuccess = col(c.onSuccess, "#213528")
                root.m3successContainer = col(c.successContainer, "#374B3E")

                /* Map to Carbon Theme variables with Caelestia's subtle alpha layering */
                if (root.isDark) {
                    root.bg = Qt.rgba(root.m3surfaceContainer.r, root.m3surfaceContainer.g, root.m3surfaceContainer.b, root.shellOpacity)
                    root.bgAlt = Qt.rgba(root.m3surfaceContainerHigh.r, root.m3surfaceContainerHigh.g, root.m3surfaceContainerHigh.b, 0.75)
                    root.bgHover = Qt.rgba(root.m3surfaceContainerHighest.r, root.m3surfaceContainerHighest.g, root.m3surfaceContainerHighest.b, 0.90)
                    root.bgActive = Qt.rgba(root.m3primaryContainer.r, root.m3primaryContainer.g, root.m3primaryContainer.b, 0.85)

                    root.fg = root.m3onSurface
                    root.fgDim = root.m3onSurfaceVariant
                    root.fgFaint = Qt.rgba(root.m3outline.r, root.m3outline.g, root.m3outline.b, 0.70)

                    root.accent = root.m3primary
                    var litCand = c.accentLit ? col(c.accentLit, "#eedbc9") : (
                        (lum(root.m3primaryContainer) > 0.5) ? root.m3primaryContainer :
                        (lum(root.m3onPrimaryContainer) > 0.5) ? root.m3onPrimaryContainer :
                        (lum(root.m3primary) > 0.5) ? root.m3primary : Qt.lighter(root.m3primary, 1.25)
                    )
                    root.accentLit = litCand
                    root.accentFg = root.m3onPrimary
                    root.accentContrast = root.m3onPrimary
                    root.outline = Qt.rgba(root.m3outlineVariant.r, root.m3outlineVariant.g, root.m3outlineVariant.b, 0.40)
                } else {
                    /* Crisp, luminous porcelain light mode */
                    root.bg = Qt.rgba(root.m3surfaceContainerLowest.r, root.m3surfaceContainerLowest.g, root.m3surfaceContainerLowest.b, root.shellOpacity)
                    root.bgAlt = Qt.rgba(root.m3surfaceContainerLow.r, root.m3surfaceContainerLow.g, root.m3surfaceContainerLow.b, 0.90)
                    root.bgHover = Qt.rgba(root.m3surfaceContainer.r, root.m3surfaceContainer.g, root.m3surfaceContainer.b, 0.95)
                    root.bgActive = Qt.rgba(root.m3primaryContainer.r, root.m3primaryContainer.g, root.m3primaryContainer.b, 0.90)

                    root.fg = root.m3onSurface
                    root.fgDim = root.m3onSurfaceVariant
                    root.fgFaint = Qt.rgba(root.m3onSurfaceVariant.r, root.m3onSurfaceVariant.g, root.m3onSurfaceVariant.b, 0.85)

                    root.accent = root.m3primary
                    root.accentLit = root.m3primaryContainer
                    root.accentFg = root.m3onPrimary
                    root.accentContrast = root.m3onPrimary
                    root.outline = Qt.rgba(0, 0, 0, 0.12)
                }

                root.ok = root.m3success
                root.warn = root.m3tertiary
                root.err = root.m3error

                console.log("[Theme] Synchronized with Caelestia Scheme:", root.schemeName, "Mode:", parsed.mode || (root.isDark ? "dark" : "light"), "Primary:", root.accent)
                return
            }

            /* Fallback to ~/.config/hypr/theme.json */
            var ftxt = fallbackFile.text().trim()
            if (ftxt.length > 0) {
                var p = JSON.parse(ftxt)
                root.palette = p
                if (p.bg) {
                    var rawBg = Qt.color(p.bg)
                    root.bg = Qt.rgba(rawBg.r, rawBg.g, rawBg.b, root.shellOpacity)
                }
                if (p.bgAlt) root.bgAlt = p.bgAlt
                if (p.bgHover) root.bgHover = p.bgHover
                if (p.bgActive) root.bgActive = p.bgActive
                if (p.fg) root.fg = p.fg
                if (p.fgDim) root.fgDim = p.fgDim
                if (p.fgFaint) root.fgFaint = p.fgFaint
                if (p.accent) root.accent = p.accent
                if (p.accentLit) root.accentLit = p.accentLit
                if (p.onAccent || p.accentFg) {
                    root.accentFg = p.accentFg || p.onAccent
                    root.accentContrast = root.accentFg
                }
                if (p.outline) root.outline = p.outline
                if (p.ok) root.ok = p.ok
                if (p.warn) root.warn = p.warn
                if (p.err) root.err = p.err
                if (p.isDark !== undefined) root.isDark = p.isDark
                console.log("[Theme] Loaded from theme.json. Accent:", root.accent)
            }
        } catch (e) {
            console.log("[Theme] Reload error: " + e)
        }
    }

    Component.onCompleted: reload()

    /* ── Standard Carbon Tokens ───────────────────────────────────────── */
    property color bg:             "#E6191920"
    property color bgAlt:          "#BF1F1F26"
    property color bgHover:        "#E624252E"
    property color bgActive:       "#D94B5074"
    property color fg:             "#E6E4F0"
    property color fgDim:          "#ABAAB5"
    property color fgFaint:        "#75747F"
    property color accent:         "#C0C4EE"
    property color accentLit:      "#E0E1FF"
    property color accentFg:       "#393E61"
    property color accentContrast: "#393E61"
    property color outline:        "#40474750"
    property color ok:             "#B5CCBA"
    property color warn:           "#FBE3FF"
    property color err:            "#F97386"
    property bool isDark:          true
    property bool dnd:             false

    /* ── Caelestia Material 3 Palette Tokens ─────────────────────────── */
    property color m3background:             "#0E0E12"
    property color m3onBackground:           "#E6E4F0"
    property color m3surface:                "#0E0E12"
    property color m3surfaceDim:             "#0E0E12"
    property color m3surfaceBright:          "#2B2B34"
    property color m3surfaceContainerLowest: "#000000"
    property color m3surfaceContainerLow:    "#131318"
    property color m3surfaceContainer:       "#191920"
    property color m3surfaceContainerHigh:   "#1F1F26"
    property color m3surfaceContainerHighest:"#24252E"
    property color m3onSurface:              "#E6E4F0"
    property color m3surfaceVariant:         "#24252E"
    property color m3onSurfaceVariant:       "#ABAAB5"
    property color m3outline:                "#75747F"
    property color m3outlineVariant:         "#474750"
    property color m3primary:                "#C0C4EE"
    property color m3primaryDim:             "#B2B6E0"
    property color m3onPrimary:              "#393E61"
    property color m3primaryContainer:       "#4B5074"
    property color m3onPrimaryContainer:     "#E0E1FF"
    property color m3secondary:              "#C4C5DD"
    property color m3onSecondary:            "#3D3F52"
    property color m3secondaryContainer:     "#383A4D"
    property color m3onSecondaryContainer:   "#BDBDD5"
    property color m3tertiary:               "#FBE3FF"
    property color m3onTertiary:             "#684D73"
    property color m3tertiaryContainer:      "#F5D1FF"
    property color m3onTertiaryContainer:    "#60446A"
    property color m3error:                  "#F97386"
    property color m3onError:                "#490013"
    property color m3errorContainer:         "#871C34"
    property color m3success:                "#B5CCBA"
    property color m3onSuccess:              "#213528"
    property color m3successContainer:       "#374B3E"

    /* ── Caelestia Design Tokens ──────────────────────────────────────── */
    readonly property QtObject tokens: QtObject {
        readonly property QtObject rounding: QtObject {
            readonly property real extraSmall: 4
            readonly property real small: 8
            readonly property real medium: 12
            readonly property real large: 16
            readonly property real largeIncreased: 20
            readonly property real extraLarge: 28
            readonly property real full: 999
        }
        readonly property QtObject spacing: QtObject {
            readonly property real extraSmall: 4
            readonly property real small: 8
            readonly property real medium: 12
            readonly property real large: 16
            readonly property real largeIncreased: 20
            readonly property real extraLarge: 28
        }
        readonly property QtObject padding: QtObject {
            readonly property real extraSmall: 4
            readonly property real small: 8
            readonly property real medium: 12
            readonly property real large: 16
            readonly property real largeIncreased: 20
            readonly property real extraLarge: 28
        }
        readonly property QtObject anim: QtObject {
            readonly property int fast: 150
            readonly property int normal: 240
            readonly property int slow: 380
        }
    }

    /* Bar geometry */
    readonly property real barWidth: 56
    readonly property real radius: 18
    readonly property real iconSize: 22
    readonly property real moduleMargin: 5

    /* Typography */
    readonly property string font: (root.customFont && root.customFont.length > 0) ? root.customFont : "Rubik, Google Sans Flex, JetBrainsMono Nerd Font, sans-serif"
    readonly property string fontMono: (root.customFontMono && root.customFontMono.length > 0) ? root.customFontMono : "JetBrainsMono Nerd Font, monospace"

    /* ── Global Font Scale — the single knob ────────────────────────── */
    // Edit this ONE number to resize every text element in the shell.
    // 1.0 = original design size.  All text sizes are wrapped in fontPx().
    readonly property real fontScale: root.customFontScale > 0 ? root.customFontScale : 1
    function fontPx(base) { return Math.round(base * fontScale) }
    readonly property string fontIcon: "Material Symbols Rounded"

    /* ── Material Design 3 Motion System ───────────────────────────── */
    readonly property int motionDurationShort1: 50
    readonly property int motionDurationShort2: 100
    readonly property int motionDurationShort3: 150
    readonly property int motionDurationShort4: 200

    readonly property int motionDurationMedium1: 250
    readonly property int motionDurationMedium2: 300
    readonly property int motionDurationMedium3: 350
    readonly property int motionDurationMedium4: 400

    readonly property int motionDurationLong1: 450
    readonly property int motionDurationLong2: 500
    readonly property int motionDurationLong3: 550
    readonly property int motionDurationLong4: 600

    readonly property int easingEmphasized: Easing.OutBack
    readonly property int easingEmphasizedDecelerate: Easing.OutCubic
    readonly property int easingEmphasizedAccelerate: Easing.InCubic
    readonly property int easingStandard: Easing.InOutQuad
    readonly property int easingStandardDecelerate: Easing.OutQuad
    readonly property int easingStandardAccelerate: Easing.InQuad

    /* ── Material Design 3 Shape System ────────────────────────────── */
    readonly property real shapeCornerNone: 0
    readonly property real shapeCornerExtraSmall: 4
    readonly property real shapeCornerSmall: 8
    readonly property real shapeCornerMedium: 12
    readonly property real shapeCornerLarge: 16
    readonly property real shapeCornerExtraLarge: 28
    readonly property real shapeCornerFull: 999
}
