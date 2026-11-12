"""Text for the release workflows (.github/workflows/release.yml and nexus.yml).

    python tools/nexus_release.py check section.md       # the release rules for a changelog
    python tools/nexus_release.py files                    # the title and description of the file on Nexus

section.md holds one version's section of CHANGELOG.md.

check: a changelog is a list, one change per line ("- New: ..."), with nothing else in it, and follows the
rules for public text: no em or en dashes, and none of the words in WORDS.

files: the upload action always sends a title (the file name, when none is given), so the workflow passes back
what the page has now and the title and description set by hand on Nexus stay. Read from the public v2 API, no
key needed. The mod has one live (MAIN) file; anything else stops the run before an upload. Prints lines for
$GITHUB_OUTPUT.
"""

import json
import re
import sys
import urllib.request

GAME_ID = 3552   # helldivers
MOD_ID = 45      # nexusmods.com/helldivers/mods/45, Unique Mod ID 15255723835437
WORDS = re.compile(r"\b(it'?s|i|me|my|we|our|us|you|your)\b", re.I)  # the possessive, and first and second person


def lines(text):
    return [s.strip() for s in text.replace("\r", "").split("\n") if s.strip()]


def check(text):
    problems = []
    entries = lines(text)
    if not entries:
        problems.append("the changelog is empty")
    for s in entries:
        if not s.startswith("- ") or len(s) < 3:
            problems.append(f"not a list entry (one change per line, starting with \"- \"): {s}")
            continue
        body = re.sub(r"`[^`]*`", "", s[2:])  # code, such as an option id, isn't prose
        hit = WORDS.search(body)
        if hit:
            problems.append(f"\"{hit.group(0)}\" in: {s}")
        if "—" in s or "–" in s:
            problems.append(f"a dash in: {s}")
    return problems


def files():
    q = {"query": f"{{ modFiles(modId: {MOD_ID}, gameId: {GAME_ID}) {{ name description category }} }}"}
    req = urllib.request.Request(
        "https://api.nexusmods.com/v2/graphql", data=json.dumps(q).encode(),
        headers={"Content-Type": "application/json", "User-Agent": "SharedResupply-release"},
    )
    with urllib.request.urlopen(req, timeout=30) as r:
        data = json.load(r)
    if data.get("errors"):
        sys.exit(f"Nexus refused the file list: {data['errors']}")
    live = [f for f in data["data"]["modFiles"] if f["category"] == "MAIN"]
    if len(live) != 1:
        sys.exit(f"Expected one live Nexus file, found {len(live)}: {[f['name'] for f in live]}. Nothing uploaded.")
    f = live[0]
    desc = (f["description"] or "").replace("\r", "")
    return f"name={f['name']}\ndescription<<DESC_END\n{desc}\nDESC_END"


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "check":
        problems = check(open(sys.argv[2], encoding="utf-8").read())
        for p in problems:
            print(f"::error file={sys.argv[2]}::{p}")
        sys.exit(1 if problems else 0)
    elif len(sys.argv) == 2 and sys.argv[1] == "files":
        print(files())
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
