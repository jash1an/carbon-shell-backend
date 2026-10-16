// VerciGlyphMap.js: 16 High-Aesthetic Song Motifs Mapper for Carbon // Verci
// Pure lookup dictionary matching stripped lowercase words strictly to
// one of the 16 solid geometric vector motif keys. ZERO Unicode text emojis!

.pragma library

var MOTIF_MAP = {
    // 1. love / heart / feel / need
    "love": "heart", "loving": "heart", "lover": "heart", "heart": "heart", "hearts": "heart",
    "feel": "heart", "feeling": "heart", "feelings": "heart", "need": "heart", "needing": "heart",
    "hug": "heart", "hugs": "heart", "kiss": "heart", "kisses": "heart", "kissing": "heart",
    "darling": "heart", "sweetheart": "heart", "passion": "heart", "soul": "heart",
    "care": "heart", "caring": "heart", "crush": "heart", "romantic": "heart",

    // 2. you / me / somebody / who / alone
    "you": "person", "me": "person", "we": "person", "us": "person", "somebody": "person",
    "someone": "person", "who": "person", "alone": "person", "boy": "person", "girl": "person",
    "man": "person", "woman": "person", "baby": "person", "babe": "person", "friend": "person",
    "friends": "person", "stranger": "person", "brother": "person", "sister": "person",
    "crowd": "person", "people": "person", "homie": "person", "crew": "person",

    // 3. car / cars / drive / driving / ride / fast
    "car": "car", "cars": "car", "drive": "car", "driving": "car", "driver": "car",
    "ride": "car", "riding": "car", "rider": "car", "fast": "car", "speed": "car",
    "racer": "car", "race": "car", "racing": "car", "drift": "car", "highway": "car",
    "road": "car", "truck": "car", "motor": "car", "engine": "car", "wheel": "car", "wheels": "car",

    // 4. start / go / play / run / move
    "start": "play", "starting": "play", "go": "play", "going": "play", "play": "play",
    "playing": "play", "run": "play", "running": "play", "runner": "play", "move": "play",
    "moving": "play", "forward": "play", "lead": "play", "jump": "play",

    // 5. chance / chances / luck / roll / bet
    "chance": "dice", "chances": "dice", "luck": "dice", "lucky": "dice", "roll": "dice",
    "rolling": "dice", "bet": "dice", "betting": "dice", "gamble": "dice", "gambling": "dice",
    "jackpot": "dice", "game": "dice", "games": "dice", "win": "dice", "winner": "dice", "winning": "dice",

    // 6. dream / dreams / dreaming / cloud / sky / high
    "dream": "cloud", "dreams": "cloud", "dreaming": "cloud", "dreamer": "cloud",
    "cloud": "cloud", "clouds": "cloud", "cloudy": "cloud", "sky": "cloud", "skies": "cloud",
    "high": "cloud", "higher": "cloud", "fly": "cloud", "flying": "cloud", "heaven": "cloud",
    "breeze": "cloud", "wind": "cloud", "air": "cloud",

    // 7. fire / burn / burning / hot / flame / smoke
    "fire": "flame", "burn": "flame", "burning": "flame", "hot": "flame", "heat": "flame",
    "flame": "flame", "flames": "flame", "smoke": "flame", "smoking": "flame", "blaze": "flame",
    "blazing": "flame", "ignite": "flame", "spark": "flame", "sparks": "flame", "ash": "flame",

    // 8. night / dark / darkest / moon / midnight
    "night": "moon", "nights": "moon", "dark": "moon", "darker": "moon", "darkest": "moon",
    "darkness": "moon", "moon": "moon", "moonlight": "moon", "midnight": "moon",
    "shadow": "moon", "shadows": "moon", "sunset": "moon", "dusk": "moon",

    // 9. star / stars / shine / miracle / beautiful / light / glow
    "star": "star", "stars": "star", "shine": "star", "shining": "star", "miracle": "star",
    "beautiful": "star", "beauty": "star", "light": "star", "lights": "star", "lighting": "star",
    "glow": "star", "glowing": "star", "bright": "star", "brighter": "star", "brightest": "star",
    "sparkle": "star", "glimmer": "star", "flash": "star", "magic": "star",

    // 10. time / wait / waitin / waiting / forever / clock
    "time": "clock", "times": "clock", "wait": "clock", "waitin": "clock", "waiting": "clock",
    "forever": "clock", "clock": "clock", "hour": "clock", "hours": "clock",
    "minute": "clock", "minutes": "clock", "second": "clock", "seconds": "clock",
    "always": "clock", "never": "clock", "late": "clock", "early": "clock", "tick": "clock",

    // 11. rain / cry / tears / water / drown / ocean
    "rain": "teardrop", "raining": "teardrop", "rainy": "teardrop", "cry": "teardrop",
    "crying": "teardrop", "tear": "teardrop", "tears": "teardrop", "water": "teardrop",
    "drown": "teardrop", "drowning": "teardrop", "ocean": "teardrop", "sea": "teardrop",
    "river": "teardrop", "drop": "teardrop", "drops": "teardrop", "pour": "teardrop",

    // 12. eyes / see / look / watch / mirror / mirrors
    "eyes": "eye", "eye": "eye", "see": "eye", "seeing": "eye", "seen": "eye",
    "look": "eye", "looking": "eye", "watch": "eye", "watching": "eye", "glance": "eye",
    "mirror": "eye", "mirrors": "eye", "vision": "eye", "blind": "eye",

    // 13. switch / button / touch / press / swish
    "switch": "hand", "button": "hand", "buttons": "hand", "touch": "hand", "touching": "hand",
    "press": "hand", "pressing": "hand", "swish": "hand", "hold": "hand", "holding": "hand",
    "grab": "hand", "grabbing": "hand", "reach": "hand", "reaching": "hand", "point": "hand",
    "clap": "hand", "fist": "hand", "hand": "hand", "hands": "hand",

    // 14. broken / hurt / pain / shame / fall
    "broken": "broken_heart", "break": "broken_heart", "breaking": "broken_heart",
    "hurt": "broken_heart", "hurting": "broken_heart", "pain": "broken_heart",
    "shame": "broken_heart", "fall": "broken_heart", "falling": "broken_heart",
    "bleed": "broken_heart", "bleeding": "broken_heart", "lost": "broken_heart",
    "scars": "broken_heart", "scar": "broken_heart",

    // 15. money / gold / rich / price / sell / sellin
    "money": "diamond", "gold": "diamond", "golden": "diamond", "rich": "diamond",
    "price": "diamond", "sell": "diamond", "sellin": "diamond", "selling": "diamond",
    "cash": "diamond", "dollar": "diamond", "dollars": "diamond", "bills": "diamond",
    "coin": "diamond", "coins": "diamond", "diamond": "diamond", "diamonds": "diamond",
    "wealth": "diamond", "pay": "diamond", "paying": "diamond", "cost": "diamond",

    // 16. music / song / sound / beat / sing
    "music": "note", "song": "note", "songs": "note", "sound": "note", "sounds": "note",
    "beat": "note", "beats": "note", "sing": "note", "singing": "note", "singer": "note",
    "dance": "note", "dancing": "note", "melody": "note", "tune": "note", "radio": "note",
    "track": "note", "guitar": "note", "bass": "note", "drum": "note", "drums": "note"
};

function stripWord(w) {
    if (!w) return "";
    return w.toLowerCase().replace(/[^a-z0-9]/g, "");
}

function lookupGlyph(word) {
    var s = stripWord(word);
    if (!s) return null;
    return MOTIF_MAP[s] || null;
}
