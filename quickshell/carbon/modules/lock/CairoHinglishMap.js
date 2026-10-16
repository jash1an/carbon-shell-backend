// CairoHinglishMap.js: 18 Custom Angular SVG Paths, Multilingual Normalizer, & Keyword Engine for Carbon // Cairo
// Strictly 0% Unicode Emojis. Native 24x24 EvenOdd SVG Paths.

.pragma library

var GLYPH_PATHS = {
    "ishq_heart": "M12 21.6 L3.2 12.8 C0.8 10.4 0.8 6.4 3.2 4.0 C5.4 1.8 8.8 1.8 11.0 4.0 L12 5.0 L13.0 4.0 C15.2 1.8 18.6 1.8 20.8 4.0 C23.2 6.4 23.2 10.4 20.8 12.8 L15.4 18.2 L17.2 11.2 L12.8 11.2 L14.4 5.8 L8.6 13.4 L12.8 13.4 L10.8 20.4 Z",
    "jaan_sparkle": "M9.5 1 L11.6 7.4 L18 9.5 L11.6 11.6 L9.5 18 L7.4 11.6 L1 9.5 L7.4 7.4 Z M18.5 13 L19.7 16.8 L23.5 18 L19.7 19.2 L18.5 23 L17.3 19.2 L13.5 18 L17.3 16.8 Z",
    "naina_eye": "M1 12 C4.2 5.5 8.2 3.5 12 3.5 C15.8 3.5 19.8 5.5 23 12 C19.8 18.5 15.8 20.5 12 20.5 C8.2 20.5 4.2 18.5 1 12 Z M12 7.2 C9.3 7.2 7.2 9.3 7.2 12 C7.2 14.7 9.3 16.8 12 16.8 C14.7 16.8 16.8 14.7 16.8 12 C16.8 9.3 14.7 7.2 12 7.2 Z M12.8 8.8 L10.4 12 L11.2 15.2 L13.6 12 Z",
    "raat_moon": "M15.8 2.2 C9.6 2.2 4.5 7.3 4.5 13.5 C4.5 18.2 7.4 22.2 11.5 23.8 C6.1 23.2 2 18.6 2 13 C2 6.9 6.9 2 13 2 C14.9 2 16.7 2.5 18.2 3.4 C17.4 2.6 16.6 2.2 15.8 2.2 Z M18 6 L19.2 9.3 L22.5 10.5 L19.2 11.7 L18 15 L16.8 11.7 L13.5 10.5 L16.8 9.3 Z",
    "gaddi_car": "M2.5 13.5 L5.8 6.5 C6.3 5.5 7.3 5 8.5 5 L15.5 5 C16.7 5 17.7 5.5 18.2 6.5 L21.5 13.5 L23 14.5 L22.2 19.5 L19.5 19.5 L19.5 17.5 L4.5 17.5 L4.5 19.5 L1.8 19.5 L1 14.5 Z M6.8 7.2 L5.2 11.2 L18.8 11.2 L17.2 7.2 Z M4.2 13.5 L8.5 14.8 L8.2 16.2 L3.8 15.2 Z M19.8 13.5 L15.5 14.8 L15.8 16.2 L20.2 15.2 Z",
    "aag_fire": "M13.5 1.5 C13.5 1.5 19.5 6.8 19.5 13.2 C19.5 18.2 15.8 22.2 11.2 22.5 C13.2 20.2 13.5 16.8 11.5 14.5 C9.8 17.2 9.2 19.5 10.2 22.2 C6.2 21.2 4.0 17.8 4.0 13.8 C4.0 10.2 6.2 7.2 6.2 7.2 C6.2 7.2 6.0 10.2 7.8 11.5 C7.2 7.2 10.2 3.8 13.5 1.5 Z",
    "baarish_drop": "M12 1.5 C12 1.5 19.5 10.2 19.5 15.5 C19.5 19.6 16.1 23 12 23 C7.9 23 4.5 19.6 4.5 15.5 C4.5 10.2 12 1.5 12 1.5 Z M9.2 12.2 L15.8 9.5 L14.8 11.8 L8.2 14.5 Z M8.5 16.5 C8.5 18.5 10.1 20.2 12.2 20.2 L12.2 18.5 C11.0 18.5 10.2 17.6 10.2 16.5 Z",
    "kismat_dice": "M3.5 5.5 L12.5 3.2 L14.8 12.2 L5.8 14.5 Z M7.2 7.2 A1.1 1.1 0 1 0 7.2 9.4 A1.1 1.1 0 1 0 7.2 7.2 Z M11.0 9.8 A1.1 1.1 0 1 0 11.0 12.0 A1.1 1.1 0 1 0 11.0 9.8 Z M11.5 15.5 L15.2 14.5 L16.2 10.8 L20.8 12.2 L18.5 20.8 L10.2 18.5 Z M15.8 15.8 A1.1 1.1 0 1 0 15.8 18.0 A1.1 1.1 0 1 0 15.8 15.8 Z",
    "taj_crown": "M2.0 19.5 L3.8 6.5 L9.2 12.2 L12.0 3.5 L14.8 12.2 L20.2 6.5 L22.0 19.5 Z M4.5 21.0 L19.5 21.0 L19.2 22.8 L4.8 22.8 Z M12.0 12.8 L10.2 15.5 L12.0 18.2 L13.8 15.5 Z",
    "dard_broken": "M11.2 4.5 L9.0 10.5 L13.2 12.2 L9.8 19.8 L3.2 13.0 C0.8 10.5 0.8 6.5 3.2 4.0 C5.4 1.8 8.8 1.8 11.2 4.5 Z M13.8 4.2 C16.0 2.0 19.2 2.2 21.2 4.4 C23.6 6.8 23.4 10.8 21.0 13.2 L12.5 21.8 L15.2 13.8 L11.0 12.0 L13.8 4.2 Z",
    "tanha_solo": "M12 2.5 C14.6 2.5 16.8 4.6 16.8 7.2 C16.8 9.8 14.6 12.0 12 12.0 C9.4 12.0 7.2 9.8 7.2 7.2 C7.2 4.6 9.4 2.5 12 2.5 Z M3.2 21.5 C3.8 16.2 7.2 13.8 12 13.8 C16.8 13.8 20.2 16.2 20.8 21.5 L14.2 21.5 L15.8 16.2 L13.8 16.2 L12.2 21.5 Z",
    "waqt_time": "M4.5 2.0 L19.5 2.0 L18.8 4.2 L13.8 11.5 L18.8 19.8 L19.5 22.0 L4.5 22.0 L5.2 19.8 L10.2 11.5 L5.2 4.2 Z M7.8 4.5 L16.2 4.5 L12.0 10.2 Z M12.0 13.8 L8.5 19.2 L15.5 19.2 Z",
    "khwab_cloud": "M6.5 19.5 C3.5 19.5 1.2 17.2 1.2 14.2 C1.2 11.6 3.1 9.4 5.6 9.0 C6.4 5.5 9.5 3.0 13.2 3.0 C17.5 3.0 21.0 6.5 21.0 10.8 C22.2 11.6 23.0 13.0 23.0 14.6 C23.0 17.3 20.8 19.5 18.0 19.5 L13.2 19.5 L15.5 12.5 L13.2 12.5 L10.8 19.5 Z",
    "sona_diamond": "M6.2 3.0 L17.8 3.0 L22.5 9.2 L12.0 21.8 L1.5 9.2 Z M7.5 5.2 L4.5 9.0 L9.2 9.0 Z M12.0 5.2 L10.2 9.0 L13.8 9.0 Z M16.5 5.2 L14.8 9.0 L19.5 9.0 Z M5.2 10.8 L10.8 18.2 L9.5 10.8 Z M13.2 18.2 L18.8 10.8 L14.5 10.8 Z",
    "dhun_play": "M3.5 4.2 L15.8 11.5 L3.5 19.8 L5.2 12.8 L10.2 11.5 L5.2 10.2 Z M18.2 6.5 L20.2 6.0 L19.0 18.0 L17.0 18.5 Z M21.5 9.2 L23.2 8.8 L22.4 15.2 L20.7 15.6 Z",
    "jaam_chalice": "M2.5 3.5 L21.5 3.5 L13.2 13.5 L13.2 19.5 L18.0 19.5 L17.4 21.8 L6.0 21.8 L6.6 19.5 L10.8 19.5 L10.8 13.5 Z M5.8 5.8 L9.8 10.6 L18.2 5.8 Z M16.5 1.2 L17.8 2.5 L16.5 3.8 L15.2 2.5 Z",
    "nasha_vortex": "M12 1.5 L22.5 12 L12 22.5 L1.5 12 Z M12 4.8 L5.5 11.3 L7.2 13.0 L12 8.2 L16.8 13.0 L12 17.8 L9.2 15.0 L7.5 16.7 L12 21.2 L19.8 13.4 L12 5.6 Z M12 10.2 L13.8 12 L12 13.8 L10.2 12 Z",
    "bijli_bolt": "M14.8 1.2 L4.2 13.2 L11.2 13.2 L8.8 22.8 L19.8 10.5 L12.8 10.5 Z"
};

var RAW_BUCKETS = {
    // 1. ISHQ_HEART
    "ishq_heart": [
        "love", "loving", "lover", "heart", "hearts", "heartbeat",
        "dil", "dila", "dilda", "pyar", "pyaar", "ishq", "ishqe", "mohabbat",
        "chahat", "dhadkan", "dilbar", "diljaniya", "premi", "aashiq", "ashiq",
        "दिल", "प्यार", "इश्क़", "मोहब्बत", "धड़कन", "चाहत"
    ],

    // 2. JAAN_SPARKLE (Replaces person/baby icon!)
    "jaan_sparkle": [
        "baby", "babe", "darling", "shawty", "honey", "angel", "beautiful", "stunning", "gorgeous",
        "jaan", "jan", "jaanu", "janu", "jana", "piya", "mahiya", "heeriye", "hiriye",
        "sohniye", "sohna", "sajna", "sajan", "sanam", "mehboob", "habibi", "kudi", "kudiye", "billo",
        "हसीन", "जान", "पिया", "सजना", "सनम", "हीरिये"
    ],

    // 3. NAINA_EYE
    "naina_eye": [
        "eye", "eyes", "look", "looking", "see", "stare", "gaze", "mirror", "mirrors", "vision",
        "naina", "nain", "naino", "akh", "akhiyan", "aankh", "aankhein", "ankhen",
        "nazar", "nazrein", "kajal", "surma", "palak", "palkein",
        "नैना", "आँख", "आँखें", "नज़र", "काजल"
    ],

    // 4. RAAT_MOON
    "raat_moon": [
        "night", "nights", "tonight", "midnight", "moon", "moonlight", "dark", "darkest", "darkness", "shadow",
        "raat", "rat", "raataan", "ratan", "raatein", "chand", "chaand", "chandni", "andhera",
        "shaam", "sham", "savera",
        "रात", "चाँद", "चाँदनी", "अंधेरा", "शाम"
    ],

    // 5. GADDI_CAR
    "gaddi_car": [
        "car", "cars", "drive", "driving", "ride", "riding", "road", "highway", "speed", "fast", "whip",
        "gaddi", "gaddiyan", "rasta", "raaste", "safar", "rah", "raah", "manzil",
        "सफ़र", "रास्ता", "गाड़ी", "मंज़िल"
    ],

    // 6. AAG_FIRE
    "aag_fire": [
        "fire", "burn", "burning", "flame", "flames", "smoke", "heat", "hot", "lit", "ashes",
        "aag", "ag", "jal", "jalna", "jale", "dhuan", "dhua", "shola", "angaare", "garmi",
        "आग", "धुआँ", "शोला"
    ],

    // 7. BAARISH_DROP
    "baarish_drop": [
        "rain", "raining", "cry", "crying", "tear", "tears", "water", "ocean", "sea", "drown", "pour",
        "baarish", "barish", "barsaat", "barsat", "saawan", "sawan", "boondein", "bheega", "bhiga",
        "aansu", "ansu", "samandar", "dariya", "paani", "pani",
        "बारिश", "आँसू", "सावन", "समंदर", "दरिया", "पानी"
    ],

    // 8. KISMAT_DICE
    "kismat_dice": [
        "chance", "chances", "luck", "lucky", "dice", "roll", "bet", "gamble", "game", "risk",
        "kismat", "taqdeer", "naseeb", "bazi", "baazi", "khel",
        "क़िस्मत", "नसीब", "बाज़ी"
    ],

    // 9. TAJ_CROWN
    "taj_crown": [
        "king", "queen", "crown", "royal", "throne", "boss", "legend",
        "taj", "badshah", "rani", "shah", "sultan", "gabru", "jatt", "sardar", "nawab",
        "ताज", "बादशाह", "रानी"
    ],

    // 10. DARD_BROKEN
    "dard_broken": [
        "broken", "break", "hurt", "pain", "bleed", "bleeding", "scar", "scars", "shame", "lie", "lies", "fake",
        "dard", "zakham", "tuta", "toota", "bewafa", "dhoka", "judai",
        "जुदाई", "दर्द", "ज़ख़्म", "बेवफ़ा", "टूटा"
    ],

    // 11. TANHA_SOLO (Strictly Solitary/Identity words. NEVER baby/boy/girl/you/me)
    "tanha_solo": [
        "alone", "lonely", "somebody", "nobody", "stranger", "myself", "yourself",
        "tanha", "akela", "akele", "khud", "ajnabi",
        "तन्हा", "अकेला", "अजनबी"
    ],

    // 12. WAQT_TIME
    "waqt_time": [
        "time", "wait", "waiting", "waitin", "forever", "always", "never", "clock", "hour", "hours", "moment", "past", "future",
        "waqt", "lamha", "lamhe", "pal", "sadiyan", "intezaar", "intezar", "hamesha",
        "वक़्त", "लम्हा", "पल", "इंतज़ार", "हमेशा"
    ],

    // 13. KHWAB_CLOUD
    "khwab_cloud": [
        "dream", "dreams", "dreaming", "sky", "skies", "cloud", "clouds", "heaven", "fly", "flying", "high", "float",
        "khwab", "khwaab", "sapna", "sapne", "aasman", "asman", "badal", "baadal", "hawa", "hawaein", "parinde",
        "ख़्वाब", "सपना", "सपने", "आसमान", "बादल", "हवा"
    ],

    // 14. SONA_DIAMOND
    "sona_diamond": [
        "diamond", "diamonds", "gold", "golden", "money", "cash", "rich", "shine", "shining", "miracle", "priceless", "treasure",
        "sona", "sone", "heera", "hira", "daulat", "paisa", "noor", "nur", "chamak", "taare", "tare", "sitara",
        "सितारा", "सोना", "हीरा", "नूर"
    ],

    // 15. DHUN_PLAY
    "dhun_play": [
        "start", "play", "music", "song", "beat", "sound", "sing", "voice", "dance", "move",
        "dhun", "geet", "gaana", "gana", "aawaz", "awaz", "sur", "saaz",
        "ताल", "धुन", "गीत", "आवाज़"
    ],

    // 16. JAAM_CHALICE
    "jaam_chalice": [
        "drink", "drinking", "sip", "cup", "glass", "wine", "liquor", "bottle", "poison", "taste",
        "sharab", "sharaab", "jaam", "jam", "maikhana", "daaru", "daru", "peg", "zahar", "zeher",
        "शराब", "जाम", "ज़हर", "पैमाना"
    ],

    // 17. NASHA_VORTEX
    "nasha_vortex": [
        "nasha", "nashe", "madhoshi", "madhosh", "khumar", "fitoor", "fitur", "junoon", "junun",
        "pagal", "deewana", "diwana", "dizzy", "trance", "crazy", "lose", "lost", "mind", "vibe",
        "नशा", "नशे", "मदहोशी", "फ़ितूर", "जुनून", "दीवाना"
    ],

    // 18. BIJLI_BOLT
    "bijli_bolt": [
        "thunder", "lightning", "electric", "electricity", "storm", "shock", "power",
        "switch", "button", "touch", "swish", "bijli", "toofan", "tufan",
        "बिजली", "तूफ़ान"
    ]
};

// Build inverted fast lookup map
var KEYWORD_MAP = {};

function initMap() {
    for (var motif in RAW_BUCKETS) {
        var words = RAW_BUCKETS[motif];
        for (var i = 0; i < words.length; i++) {
            var raw = words[i].trim().toLowerCase();
            if (raw.length > 0) {
                KEYWORD_MAP[raw] = motif;
            }
        }
    }
}
initMap();

/**
 * 1. Convert to lowercase & strip punctuation (/[.,!?;:'"()\[\]\-]/g)
 */
function normalizeLyricToken(rawWord) {
    if (!rawWord) return "";
    var s = String(rawWord).toLowerCase().trim();
    s = s.replace(/[.,!?;:'"()\[\]\-\/\`~@#$%^&*+=<>_{}]/g, "");
    return s;
}

/**
 * 2. Hinglish Stretched-Vowel Stemmer:
 *    - aa+ -> a
 *    - ee+ -> i
 *    - oo+ -> u
 *    - 3+ identical repeated letter collapse
 */
function stemHinglish(token) {
    if (!token || token.length < 3) return token;
    var s = token;
    s = s.replace(/(.)\1{2,}/g, "$1");
    s = s.replace(/aa+/g, "a");
    s = s.replace(/ee+/g, "i");
    s = s.replace(/oo+/g, "u");
    return s;
}

/**
 * 3. Strip common plural/oblique Hinglish suffixes:
 *    -iyaan, -iyan, -eyan, -aan, -ein, -on, -an
 */
function stripHinglishSuffix(token) {
    if (!token || token.length <= 3) return token;
    var s = token;
    if (s.endsWith("iyaan") && s.length > 5) return s.slice(0, -5);
    if (s.endsWith("iyan") && s.length > 4) return s.slice(0, -4);
    if (s.endsWith("eyan") && s.length > 4) return s.slice(0, -4);
    if (s.endsWith("aan") && s.length > 3) return s.slice(0, -3);
    if (s.endsWith("ein") && s.length > 3) return s.slice(0, -3);
    if (s.endsWith("on") && s.length > 3) return s.slice(0, -2);
    if (s.endsWith("an") && s.length > 3) return s.slice(0, -2);
    return s;
}

/**
 * Lookup glyph by word:
 * Direct -> Stemmed -> Suffix-stripped
 */
function lookupGlyph(rawWord) {
    if (!rawWord) return "";
    var norm = normalizeLyricToken(rawWord);
    if (!norm) return "";

    if (KEYWORD_MAP[norm]) return KEYWORD_MAP[norm];

    var stemmed = stemHinglish(norm);
    if (KEYWORD_MAP[stemmed]) return KEYWORD_MAP[stemmed];

    var suffStripped = stripHinglishSuffix(stemmed);
    if (KEYWORD_MAP[suffStripped]) return KEYWORD_MAP[suffStripped];

    var directSuff = stripHinglishSuffix(norm);
    if (KEYWORD_MAP[directSuff]) return KEYWORD_MAP[directSuff];

    return "";
}
