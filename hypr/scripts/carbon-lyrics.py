#!/usr/bin/env python3
"""
carbon-lyrics.py: Fast, lightweight synced lyrics fetcher with disk caching.
Queries LRCLIB API and returns parsed timestamped lyrics in JSON format.
"""

import os
import sys
import json
import re
import hashlib
import urllib.request
import urllib.parse
import argparse

CACHE_DIR = "/tmp/carbon-lyrics-cache"
os.makedirs(CACHE_DIR, exist_ok=True)

def sanitize_str(s):
    return s.strip() if s else ""

def clean_text(s):
    if not s:
        return ""
    # Remove bracketed metadata
    t = re.sub(r"\((?:official|video|audio|lyric|lyrics|music video|visualizer|remaster|hd|4k|clip|prod\.|produced).*?\)", "", s, flags=re.IGNORECASE)
    t = re.sub(r"\[(?:official|video|audio|lyric|lyrics|music video|visualizer|remaster|hd|4k|clip|prod\.|produced).*?\]", "", t, flags=re.IGNORECASE)
    t = re.sub(r"\(feat\..*?\)", "", t, flags=re.IGNORECASE)
    t = re.sub(r"\(with.*?\)", "", t, flags=re.IGNORECASE)
    t = re.sub(r"\[feat\..*?\]", "", t, flags=re.IGNORECASE)
    # Remove common video descriptors
    t = re.sub(r"\b(?:tiktok remix|tiktok version|slowed\s*\+?\s*reverb|speed\s*up)\b.*", "", t, flags=re.IGNORECASE)
    t = re.sub(r" - [0-9]{4} Remaster.*", "", t, flags=re.IGNORECASE)
    return re.sub(r"\s+", " ", t).strip()

def strip_all_brackets(s):
    if not s:
        return ""
    return re.split(r"[\(\[\{]", s)[0].strip()

def parse_lrc(lrc_text):
    lines = []
    if not lrc_text:
        return lines
    for raw_line in lrc_text.splitlines():
        # Match leading [mm:ss.xx] or [mm:ss]
        m = re.match(r"^\[(\d+):(\d+(?:\.\d+)?)\]\s*(.*)$", raw_line.strip())
        if m:
            mins = int(m.group(1))
            secs = float(m.group(2))
            t = round(mins * 60 + secs, 2)
            raw_body = m.group(3).strip()
            if not raw_body:
                continue

            # Check for inline rich word timestamps: <mm:ss.xx> word or [mm:ss.xx] word
            word_pattern = r'(?:<|\[)(\d+):(\d+(?:\.\d+)?)(?:>|\])\s*([^<\[\n]+)'
            matches = list(re.finditer(word_pattern, raw_body))
            if matches:
                word_tokens = []
                for wm in matches:
                    w_mins = int(wm.group(1))
                    w_secs = float(wm.group(2))
                    w_t = round(w_mins * 60 + w_secs, 3)
                    w_txt = wm.group(3).strip()
                    if w_txt:
                        word_tokens.append({"text": w_txt, "time": w_t})
                if word_tokens:
                    clean_txt = " ".join(w["text"] for w in word_tokens)
                    lines.append({"time": t, "text": clean_txt, "words": word_tokens})
                    continue

            # Standard line: clean any residual bracket metadata
            clean_txt = re.sub(r"<[^>]+>", "", raw_body).strip()
            if clean_txt:
                lines.append({"time": t, "text": clean_txt})
    return sorted(lines, key=lambda x: x["time"])

def get_cache_path(title, artist):
    key = f"{artist.lower().strip()}::{title.lower().strip()}"
    h = hashlib.md5(key.encode("utf-8")).hexdigest()
    return os.path.join(CACHE_DIR, f"{h}.json")

def get_candidates(title, artist):
    cands = []
    seen = set()

    def add(a, t):
        a_c = clean_text(a)
        t_c = clean_text(t)
        if (a_c, t_c) not in seen and (a_c or t_c):
            seen.add((a_c, t_c))
            cands.append((a_c, t_c))

    # 1. If dash in title (YouTube title format: "Artist - Title")
    dash_match = re.search(r"\s+[-–—]\s+", title)
    if dash_match:
        left = title[:dash_match.start()].strip()
        right = title[dash_match.end():].strip()

        core_left = strip_all_brackets(left)
        core_right = strip_all_brackets(right)
        first_artist = re.split(r"[,&/]|feat\.", core_left)[0].strip()

        if core_left and core_right:
            add(core_left, core_right)
        if first_artist and first_artist != core_left and core_right:
            add(first_artist, core_right)
        add(left, right)

    # 2. Direct artist and title variations
    core_title = strip_all_brackets(title)
    clean_t = clean_text(title)
    if artist and core_title:
        add(artist, core_title)
    if artist and clean_t:
        add(artist, clean_t)
    if title:
        add("", core_title or clean_t)

    return cands

def fetch_from_lrclib(title, artist, duration=None):
    candidates = get_candidates(title, artist)
    target_dur = 0.0
    if duration:
        try:
            target_dur = float(duration)
        except Exception:
            target_dur = 0.0

    # 1. Try direct exact match via /api/get for each candidate
    for cand_artist, cand_track in candidates:
        if not cand_track:
            continue
        params = {"track_name": cand_track}
        if cand_artist:
            params["artist_name"] = cand_artist
        if target_dur > 0:
            params["duration"] = str(int(target_dur))

        url = f"https://lrclib.net/api/get?{urllib.parse.urlencode(params)}"
        req = urllib.request.Request(url, headers={"User-Agent": "CarbonBar/1.0"})
        try:
            with urllib.request.urlopen(req, timeout=3.0) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                synced = data.get("syncedLyrics")
                if synced:
                    parsed = parse_lrc(synced)
                    if parsed:
                        return parsed
        except Exception:
            pass

    # 2. Try search queries via /api/search
    search_queries = []
    seen_q = set()
    for cand_artist, cand_track in candidates:
        if cand_track:
            q = f"{cand_artist} {cand_track}".strip()
            if q and q not in seen_q:
                seen_q.add(q)
                search_queries.append(q)

    clean_full = clean_text(title)
    if clean_full and clean_full not in seen_q:
        search_queries.append(clean_full)

    for q in search_queries[:4]:
        url_search = f"https://lrclib.net/api/search?q={urllib.parse.quote(q)}"
        req_s = urllib.request.Request(url_search, headers={"User-Agent": "CarbonBar/1.0"})
        try:
            with urllib.request.urlopen(req_s, timeout=3.5) as resp:
                results = json.loads(resp.read().decode("utf-8"))
                if results and isinstance(results, list):
                    synced_items = [it for it in results if it.get("syncedLyrics")]
                    if synced_items:
                        if target_dur > 0:
                            synced_items.sort(key=lambda x: abs(float(x.get("duration", 0)) - target_dur))
                        return parse_lrc(synced_items[0]["syncedLyrics"])
        except Exception:
            pass

    return []

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--title", default="")
    parser.add_argument("--artist", default="")
    parser.add_argument("--duration", default="0")
    parser.add_argument("--current", action="store_true")
    args = parser.parse_args()

    title = args.title
    artist = args.artist
    duration = args.duration

    if args.current or (not title and not artist):
        try:
            import subprocess
            meta = subprocess.check_output(
                ["playerctl", "metadata", "--format", "{{title}}|||{{artist}}|||{{mpris:length}}"],
                stderr=subprocess.DEVNULL
            ).decode("utf-8").strip()
            parts = meta.split("|||")
            if len(parts) >= 2:
                title = parts[0].strip()
                artist = parts[1].strip()
            if len(parts) >= 3 and parts[2].isdigit():
                duration = str(int(parts[2]) / 1000000)
        except Exception:
            pass

    if not title:
        print(json.dumps({"found": False, "lines": []}))
        return

    cache_file = get_cache_path(title, artist)
    if os.path.isfile(cache_file):
        try:
            with open(cache_file, "r", encoding="utf-8") as f:
                cached_data = json.load(f)
                if cached_data.get("found"):
                    print(json.dumps(cached_data))
                    return
        except Exception:
            pass

    lines = fetch_from_lrclib(title, artist, duration)
    result = {
        "found": len(lines) > 0,
        "title": title,
        "artist": artist,
        "lines": lines
    }

    if result["found"]:
        try:
            with open(cache_file, "w", encoding="utf-8") as f:
                json.dump(result, f)
        except Exception:
            pass

    print(json.dumps(result))

if __name__ == "__main__":
    main()
