"""Refresh pinned Reicon source assets; does not follow upstream main."""
import hashlib
import json
import pathlib
import urllib.request

root = pathlib.Path(__file__).resolve().parents[1] / "assets/icons/reicon"
manifest = json.loads((root / "sources.json").read_text())
base = "https://raw.githubusercontent.com/dqev/reicon/" + manifest["revision"] + "/"
data = urllib.request.urlopen(base + manifest["source"], timeout=60).read()
if hashlib.sha256(data).hexdigest() != manifest["source_sha256"]:
    raise SystemExit("Upstream icon data hash mismatch")
icons = json.loads(data)["categories"]
for asset in manifest["icons"]:
    category, name = asset["source"].split("/")
    svg = ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24" color="#ffffff">'
           + icons[category][name]["code"] + '</svg>\n').encode()
    if hashlib.sha256(svg).hexdigest() != asset["sha256"]:
        raise SystemExit("Pinned SVG hash mismatch: " + name)
    (root / asset["file"]).write_bytes(svg)
license_data = urllib.request.urlopen(base + "LICENSE", timeout=60).read()
if hashlib.sha256(license_data).hexdigest() != manifest["license_sha256"]:
    raise SystemExit("Upstream license hash mismatch")
(root / "LICENSE").write_bytes(license_data)
print("Restored 14 pinned Reicon filled SVGs and their MIT license")
