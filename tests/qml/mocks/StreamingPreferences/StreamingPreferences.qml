pragma Singleton
import QtQuick 2.9

// The preferences the settings pages read and write, with the
// production enum names. Defaults match a fresh install.
QtObject {
    enum AudioConfig { AC_STEREO, AC_51_SURROUND, AC_71_SURROUND }
    enum VideoCodecConfig { VCC_AUTO, VCC_FORCE_H264, VCC_FORCE_HEVC, VCC_FORCE_HEVC_HDR_DEPRECATED, VCC_FORCE_AV1, VCC_FORCE_PYROWAVE }
    enum VideoDecoderSelection { VDS_AUTO, VDS_FORCE_HARDWARE, VDS_FORCE_SOFTWARE }
    enum RendererSelection { RS_AUTO, RS_VULKAN, RS_METAL, RS_AVSBDL }
    enum WindowMode { WM_FULLSCREEN, WM_FULLSCREEN_DESKTOP, WM_WINDOWED }
    enum UIDisplayMode { UI_WINDOWED, UI_MAXIMIZED, UI_FULLSCREEN }
    enum CaptureSysKeysMode { CSK_OFF, CSK_FULLSCREEN, CSK_ALWAYS }
    enum SteamControllerGrips { SCG_PADDLES, SCG_DS4, SCG_OFF }
    enum Language { LANG_AUTO, LANG_EN, LANG_FR, LANG_ZH_CN, LANG_DE, LANG_NB_NO, LANG_RU, LANG_ES, LANG_JA, LANG_VI,
                    LANG_TH, LANG_KO, LANG_HU, LANG_NL, LANG_SV, LANG_TR, LANG_UK, LANG_ZH_TW, LANG_PT, LANG_PT_BR,
                    LANG_EL, LANG_IT, LANG_HI, LANG_PL, LANG_CS, LANG_HE, LANG_CKB, LANG_LT, LANG_ET, LANG_BG, LANG_EO, LANG_TA }

    property int width: 1280
    property int height: 720
    property int fps: 60
    property int bitrateKbps: 10000
    property bool autoAdjustBitrate: true
    property bool unlockBitrate: false
    property int videoCodecConfig: 0
    property bool enableHdr: false
    property bool enableYUV444: false
    property int pyroWavePaceMbps: 0
    property int windowMode: 0
    property int recommendedFullScreenMode: 1
    property bool enableVsync: true
    property bool framePacing: false
    property bool enableVrr: false
    property int vrrBufferPerMille: 1000
    property int vrrTargetHundredths: 9950
    property int vrrHistorySeconds: 120
    property int vrrToleranceUs: 500
    property bool smoothVrrFrameTiming: false
    property bool absorbVrrMicrostutter: false
    property bool highPerformanceGpuPower: false
    property int audioConfig: 0
    property bool playAudioOnHost: false
    property bool muteOnFocusLoss: true
    property bool absoluteMouseMode: false
    property int captureSysKeysMode: 0
    property bool absoluteTouchMode: false
    property bool swapMouseButtons: false
    property bool reverseScrollDirection: false
    property bool swapFaceButtons: false
    property bool couchUi: true
    property bool multiController: true
    property bool gamepadMouse: true
    property bool backgroundGamepad: false
    property bool steamControllerDriver: true
    property bool steamControllerMotion: true
    property bool steamControllerSplitPads: true
    property int steamControllerGrips: 0
    property int steamControllerRumbleHold: 500
    property bool steamControllerStickStretch: false
    property int steamControllerHapticBoost: 0
    property int steamControllerHapticPulseScale: 100
    property int steamControllerHapticMasterGain: 0
    property bool gameOptimizations: true
    property bool quitAppAfter: false
    property int language: 0
    property int uiDisplayMode: 0
    property bool connectionWarnings: true
    property bool hideVrrBufferWarnings: false
    property bool configurationWarnings: true
    property bool richPresence: true
    property bool keepAwake: true
    property int videoDecoderSelection: 0
    property int rendererSelection: 0
    property bool enableMdns: true
    property bool detectNetworkBlocking: true
    property bool showPerformanceOverlay: false
    property bool showFrametimeGraph: false
    property bool traceVrrFrames: false
    property bool exportingDiagnostics: false
    property string diagnosticsStatus: ""
    property int saves: 0

    // Roughly the production curve: 10 Mbps at 720p60
    function getDefaultBitrate(w, h, f, yuv444) {
        var kbps = Math.round(w * h * f / (1280 * 720 * 60) * 10000 / 500) * 500
        return yuv444 ? kbps * 2 : kbps
    }
    function getDefaultPyroWaveBitrate(w, h, f, yuv444, hdr) {
        return getDefaultBitrate(w, h, f, yuv444) * 20
    }
    function getFpsChoices(refreshRates) {
        var list = [30, 60]
        for (var i = 0; i < refreshRates.length; i++) {
            if (list.indexOf(refreshRates[i]) < 0) list.push(refreshRates[i])
        }
        if (list.indexOf(fps) < 0) list.push(fps)
        return list.map(function(rate) {
            return { kind: list.indexOf(rate) < 2 || refreshRates.indexOf(rate) >= 0 ? "" : "custom",
                     video_fps: rate, is_custom: list.indexOf(rate) >= 2 && refreshRates.indexOf(rate) < 0 }
        })
    }
    // 0 is Smooth, 1 Balanced, 2 Low Latency, as in production
    function applyVrrPreset(mode) {
        var values = mode === 2 ? [500, 9900, 60] : mode === 0 ? [4000, 9995, 300] : [1000, 9950, 120]
        vrrBufferPerMille = values[0]
        vrrTargetHundredths = values[1]
        vrrHistorySeconds = values[2]
        vrrToleranceUs = 500
    }
    function save() { saves++ }
    function retranslate() { return true }
    function exportLatestDiagnostics() {}
    function openDiagnosticsFolder() {}
}
