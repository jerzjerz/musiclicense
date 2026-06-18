#!/usr/bin/env python3
"""Fetch accurate music data for one artist from the Spotify Web API.

This covers the project's accuracy-first signals that Spotify exposes reliably:
followers, popularity (0-100), genres, catalog size (albums + singles), and the
label on a recent release. It uses the Client Credentials flow — no user login,
just an app's client id/secret — so it can run unattended.

What Spotify does NOT give and you must source elsewhere (web search / a chart
vendor like Chartmetric), tagging source + confidence:
  - absolute stream counts and monthly listeners
  - album sales

Credentials: set SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET (e.g. in a .env that
you export). If they're absent this script exits cleanly with {"available": false}
so the skill knows to fall back to web search rather than crashing.

Usage:
  python spotify.py "Artist Name"          # search by name, take best match
  python spotify.py --id <spotify_artist_id>
Prints a JSON object to stdout.

Dependencies: standard library only (urllib) — no pip install needed.
"""
import base64
import json
import os
import sys
import argparse
import urllib.parse
import urllib.request

TOKEN_URL = "https://accounts.spotify.com/api/token"
API = "https://api.spotify.com/v1"


def _get_token():
    cid = os.environ.get("SPOTIFY_CLIENT_ID")
    secret = os.environ.get("SPOTIFY_CLIENT_SECRET")
    if not cid or not secret:
        return None
    auth = base64.b64encode(f"{cid}:{secret}".encode()).decode()
    body = urllib.parse.urlencode({"grant_type": "client_credentials"}).encode()
    req = urllib.request.Request(
        TOKEN_URL, data=body,
        headers={"Authorization": f"Basic {auth}",
                 "Content-Type": "application/x-www-form-urlencoded"},
    )
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r).get("access_token")


def _api(token, path, params=None):
    url = f"{API}{path}"
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)


def _search_artist(token, name):
    data = _api(token, "/search", {"q": name, "type": "artist", "limit": 1})
    items = data.get("artists", {}).get("items", [])
    return items[0] if items else None


def _catalog_count(token, artist_id):
    """Total albums + singles. Use the paging 'total' rather than fetching every page."""
    data = _api(token, f"/artists/{artist_id}/albums",
                {"include_groups": "album,single", "limit": 1, "market": "US"})
    return data.get("total")


def _recent_label(token, artist_id):
    """Label is per-release, not per-artist. Read it off the most recent album."""
    data = _api(token, f"/artists/{artist_id}/albums",
                {"include_groups": "album,single", "limit": 1, "market": "US"})
    items = data.get("items", [])
    if not items:
        return None
    album = _api(token, f"/albums/{items[0]['id']}")
    return album.get("label")


def fetch(name=None, artist_id=None):
    token = _get_token()
    if not token:
        return {"available": False,
                "reason": "SPOTIFY_CLIENT_ID/SECRET not set — fall back to web search."}
    artist = _api(token, f"/artists/{artist_id}") if artist_id else _search_artist(token, name)
    if not artist:
        return {"available": True, "found": False, "query": name}
    aid = artist["id"]
    return {
        "available": True,
        "found": True,
        "id": aid,
        "name": artist.get("name"),
        "followers": artist.get("followers", {}).get("total"),
        "popularity": artist.get("popularity"),   # 0-100, Spotify's own
        "genres": artist.get("genres", []),
        "catalog_count": _catalog_count(token, aid),
        "label": _recent_label(token, aid),
        "spotify_url": artist.get("external_urls", {}).get("spotify"),
        # Not available from this API — fill via web search and tag confidence:
        "monthly_listeners": None,
        "stream_count": None,
        "album_sales": None,
    }


def main():
    ap = argparse.ArgumentParser(description="Fetch one artist's Spotify data.")
    ap.add_argument("name", nargs="?", help="Artist name to search")
    ap.add_argument("--id", dest="artist_id", help="Spotify artist id")
    args = ap.parse_args()
    if not args.name and not args.artist_id:
        ap.error("provide an artist name or --id")
    result = fetch(name=args.name, artist_id=args.artist_id)
    json.dump(result, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
