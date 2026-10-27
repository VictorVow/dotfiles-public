#!/usr/bin/env python3
"""logseq-enrich.py — group, retitle and cross-link the children of a Logseq block.

Usage:
  logseq-enrich.py dump    <graph> <root-uuid>
  logseq-enrich.py index   <graph> [--refresh]
  logseq-enrich.py related <graph> <root-uuid> [--top=N] [--min=SCORE]
  logseq-enrich.py apply   <plan.json> [--dry-run]

Scratch files go to /tmp/logseq-enrich/<root-uuid>/ (the index is shared:
/tmp/logseq-enrich/index-<graph>.json, reused for a day unless --refresh).

dump     Live tree under the root -> children.json, and prints an outline:
         every link block with its db-id, cleaned link text, URL, whether it
         gets a gfw widget, and any existing Related: refs. Existing H2/H3
         heading children (from an earlier run) are shown with their blocks.
related  For every link block under the root, candidate blocks elsewhere in
         the graph (outside the root's subtree and outside Related: blocks):
         same URL / same GitHub repo / same Reddit or HN post first, then
         title-keyword matches ranked by IDF. Writes related.json and prints a
         compact list for picking. Needs `index` first (runs it if missing).
         --top (default 6) caps candidates per link; --min (default 12) drops
         weak keyword matches (a same-URL/repo/post match scores 100+).
apply    Executes an approved plan (format below), idempotently: creates the
         missing headings at the end of the root, moves the grouped blocks
         into them, moves the ungrouped blocks after the headings (original
         order), rewrites link text + adds gfw widgets, and adds Related:
         children with one [[uuid]] ref each. Root children the plan doesn't
         mention count as ungrouped. --dry-run prints the ops and runs the
         CLI's own dry run for `would-create-pages` on all new content.

Plan format (block ids are db-ids from dump; related values are uuids):
  {"graph": "logseq-apex", "root": "<uuid>",
   "groups": [{"h2": "AI coding agents", "h3": [{"title": "Orchestrators", "blocks": [621636]}]},
              {"h2": null, "h3": [{"title": "Kingdom Come mods", "blocks": [621679, 621680]}]}],
   "ungrouped": [621634],
   "related": {"621635": ["<uuid>", "<uuid>"]},
   "titles": {"621680": "Kingdom Come - Together"}}
"titles" (optional) overrides the cleaned link text where linktext() gets it
wrong; the URL and the rest of the block are kept.

Blocks are moved with `logseq upsert block --id <id> --target-id <parent>
--pos last-child`, which keeps their uuids and children.
"""
import json
import math
import os
import re
import subprocess
import sys
import time
from collections import defaultdict
from urllib.parse import parse_qs, urlparse

# shared with the other Logseq skills (sibling skill dir; abspath, not realpath)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "../../logseq-add-md-to-blocks/scripts"))
from logseq_links import GH_INLINE_RE, gfw_block, relink, split_link  # noqa: E402

SCRATCH = "/tmp/logseq-enrich"
RELATED = "Related:"
ID_PARAMS = ("q", "k", "v", "id", "p", "t", "query", "search", "book_id", "list")
TREE_PULL = ("[:find (pull ?p [:db/id :block/uuid :block/title :block/order "
             ":logseq.property/heading {:block/_parent 6}]) :in $ ?u "
             ":where [?p :block/uuid ?u]]")
URL_RE = re.compile(r'https?://[^\s)\]>}"]+')
REF_ONLY_RE = re.compile(r'^\s*(?:\[\[[^\]]+\]\]\s*)+$')
REF_RE = re.compile(r'\[\[([0-9a-f-]{36})\]\]')
WORD_RE = re.compile(r"[a-z0-9][a-z0-9+_.-]*[a-z0-9+]|[a-z0-9]")
STOP = set("""a about above after again all also an and any are as at be because been
before being between both but by can could did do does doing down during each few for
from further had has have having he her here hers him his how i if in into is it its
just me more most my no nor not now of off on once only or other our out over own same
she should so some such than that the their them then there these they this those
through to too under until up very was we were what when where which while who whom why
will with you your yours via vs new using use used get got one two way ways best free
open source app apps tool tools guide comments comment thread reddit github issue pull
request release releases feature support add adds added make makes making based your
like just really any anyone thoughts question help need want r www com org html""".split())


def run(args, check=True):
    r = subprocess.run(["logseq", *args], capture_output=True, text=True)
    try:
        d = json.loads(r.stdout)
    except json.JSONDecodeError:
        if check:
            sys.exit(f"logseq {' '.join(args[:3])}: {r.stdout or r.stderr}")
        return None
    if check and d.get("status") != "ok":
        sys.exit(f"logseq {' '.join(args[:3])} failed: {d.get('error')}")
    return d


def query(graph, q, inputs=None, timeout=None):
    args = ["query", "-g", graph, "--query", q, "-o", "json"]
    if inputs:
        args += ["--inputs", inputs]
    if timeout:
        args += ["--timeout-ms", str(timeout)]
    return run(args)["data"]["result"]


def scratch(root):
    d = os.path.join(SCRATCH, root)
    os.makedirs(d, exist_ok=True)
    return d


# ---------------------------------------------------------------- tree / dump

def kids(b):
    return sorted(b.get("block/_parent", []), key=lambda c: c.get("block/order", ""))


def fetch_tree(graph, root):
    rows = query(graph, TREE_PULL, f'[#uuid "{root}"]')
    if not rows:
        sys.exit(f"no block with uuid {root}")
    return rows[0][0]


def related_child(b):
    for c in kids(b):
        if c.get("block/title", "").strip() == RELATED:
            return c
    return None


def related_refs(b):
    rc = related_child(b)
    if not rc:
        return []
    return [m for c in kids(rc) for m in REF_RE.findall(c.get("block/title", ""))]


def is_heading(b, level=None):
    h = b.get("logseq.property/heading")
    return h is not None and (level is None or h == level)


def layout(tree):
    """Root children split into headings and link blocks.

    Returns (h2s, top_h3s, blocks): h2s = {title: (h2, {h3 title: h3})},
    top_h3s = {title: h3}, blocks = [(block, parent)] for every non-heading
    block found at root level or inside an H2/H3, in display order."""
    h2s, top_h3s, blocks = {}, {}, []

    def take_h3(h3):
        for c in kids(h3):
            blocks.append((c, h3))

    for c in kids(tree):
        if is_heading(c, 2):
            subs = {}
            for s in kids(c):
                if is_heading(s, 3):
                    subs[s["block/title"]] = s
                    take_h3(s)
                else:
                    blocks.append((s, c))
            h2s[c["block/title"]] = (c, subs)
        elif is_heading(c, 3):
            top_h3s[c["block/title"]] = c
            take_h3(c)
        else:
            blocks.append((c, tree))
    return h2s, top_h3s, blocks


def new_title(t):
    return gfw_block(relink(t))


def cmd_dump(graph, root):
    tree = fetch_tree(graph, root)
    h2s, top_h3s, blocks = layout(tree)
    out = os.path.join(scratch(root), "children.json")
    with open(out, "w") as f:
        json.dump(tree, f, ensure_ascii=False)
    links = 0
    print(f"# {tree.get('block/title', '')[:100]}  ({len(blocks)} blocks, "
          f"{len(h2s)} H2, {sum(len(s) for _, s in h2s.values()) + len(top_h3s)} H3)")
    for b, p in blocks:
        t = b.get("block/title", "")
        parts = split_link(t)
        loc = "" if p is tree else f"  [in: {p['block/title'][:40]}]"
        if parts:
            links += 1
            nt = new_title(t)
            text = split_link(nt)[1]
            flags = ("gfw " if "{{renderer :gfw" in nt else "") + \
                    ("retitle " if split_link(t)[1] != text else "")
            refs = related_refs(b)
            print(f"{b['db/id']}  {text[:90]}  <{parts[2][:90]}>  {flags.strip()}"
                  f"{'  related=' + str(len(refs)) if refs else ''}{loc}")
        else:
            print(f"{b['db/id']}  (not a link) {t[:100].replace(chr(10), ' ⏎ ')}{loc}")
    print(f"\n{links} link blocks; tree saved to {out}")


# ---------------------------------------------------------------- index / related

def index_path(graph):
    return os.path.join(SCRATCH, f"index-{graph}.json")


def cmd_index(graph, refresh=False):
    p = index_path(graph)
    if not refresh and os.path.exists(p) and time.time() - os.path.getmtime(p) < 86400:
        print(f"index {p} is fresh (use --refresh to rebuild)")
        return
    os.makedirs(SCRATCH, exist_ok=True)
    t0 = time.time()
    blocks = query(graph, "[:find ?b ?u ?t ?p ?pg :where [?b :block/title ?t] "
                          "[?b :block/uuid ?u] [?b :block/parent ?p] [?b :block/page ?pg]]",
                   timeout=300000)
    pages = query(graph, "[:find ?pg ?t :where [?pg :block/name] [?pg :block/title ?t]]",
                  timeout=120000)
    # pages and blocks in the recycle bin
    deleted = query(graph, "[:find ?b :where [?b :logseq.property/deleted-at]]")
    with open(p, "w") as f:
        json.dump({"blocks": blocks, "pages": pages, "deleted": [r[0] for r in deleted]},
                  f, ensure_ascii=False)
    print(f"indexed {len(blocks)} blocks, {len(pages)} pages in {time.time() - t0:.0f}s -> {p}")


def url_keys(url):
    """Keys under which two URLs count as the same thing."""
    try:
        p = urlparse(url.rstrip(".,;:"))
    except ValueError:
        return set()
    host = re.sub(r'^(?:www|m|old|mobile)\.', '', p.netloc.lower())
    path = p.path.rstrip("/")
    # the query string identifies the page for searches, videos, items
    # (q=, v=, id=…); other params (utm_, ref, crid…) are noise
    qs = parse_qs(p.query)
    ident = "&".join(f"{k}={qs[k][0].lower()}" for k in ID_PARAMS if k in qs)
    keys = {f"url:{host}{path}" + (f"?{ident}" if ident else "")}
    m = re.match(r'^/r/[^/]+/comments/([a-z0-9]+)', path, re.I)
    if m:  # reddit and its frontends (redlib instances etc.)
        keys = {f"reddit:{m.group(1).lower()}"}
    if host == "news.ycombinator.com":
        hid = parse_qs(p.query).get("id")
        if hid:
            keys = {f"hn:{hid[0]}"}
    if host == "github.com":
        m = re.match(r'^/([\w.-]+)/([\w.-]+)', path)
        if m:
            keys.add(f"repo:{m.group(1).lower()}/{m.group(2).lower().removesuffix('.git')}")
    return keys


def words(text):
    text = URL_RE.sub(" ", text)
    text = re.sub(r'\{\{[^}]*\}\}', ' ', text)
    text = REF_RE.sub(" ", text).lower()
    return {w for w in WORD_RE.findall(text) if len(w) >= 3 and w not in STOP
            and not w.isdigit()}


def link_terms(title):
    parts = split_link(title)
    text, url = parts[1], parts[2]
    ws = words(text.replace("\\#", "#"))
    m = re.match(r'^https://github\.com/[\w.-]+/([\w.-]+)', url)
    if m:  # repo name, whole and split on separators
        repo = m.group(1).lower()
        ws |= {repo} | {w for w in re.split(r'[-_.]', repo) if len(w) >= 3 and w not in STOP}
    return ws, url_keys(url)


def cmd_related(graph, root, top=6, min_score=12):
    if not os.path.exists(index_path(graph)):
        cmd_index(graph)
    tree = fetch_tree(graph, root)
    _, _, blocks = layout(tree)
    links = [b for b, _ in blocks if split_link(b.get("block/title", ""))]
    with open(index_path(graph)) as f:
        idx = json.load(f)
    pages = dict(map(tuple, idx["pages"]))
    rows = idx["blocks"]
    by_id = {r[0]: r for r in rows}
    children = defaultdict(list)
    for r in rows:
        children[r[3]].append(r[0])

    # excluded: the root's subtree, everything under a Related: block, and
    # the recycle bin
    root_id = tree["db/id"]
    deleted = set(idx.get("deleted", []))
    excluded, stack = {root_id}, [root_id]
    stack += [r[0] for r in rows if r[2].strip() == RELATED or r[0] in deleted]
    excluded.update(r[0] for r in rows if r[4] in deleted)
    excluded.update(stack)
    while stack:
        for c in children.get(stack.pop(), []):
            if c not in excluded:
                excluded.add(c)
                stack.append(c)

    want_words, want_keys, terms = set(), set(), {}
    for b in links:
        ws, ks = link_terms(new_title(b["block/title"]))
        terms[b["db/id"]] = (ws, ks)
        want_words |= ws
        want_keys |= ks

    df = defaultdict(int)
    postings, key_hits = defaultdict(set), defaultdict(set)
    for r in rows:
        bid, title = r[0], r[2]
        ws = words(title)
        for w in ws:
            df[w] += 1
        if bid in excluded or REF_ONLY_RE.match(title):
            continue
        for w in ws & want_words:
            postings[w].add(bid)
        for u in URL_RE.findall(title):
            for k in url_keys(u) & want_keys:
                key_hits[k].add(bid)
    n = len(rows)
    idf = {w: math.log(n / (1 + df[w])) for w in want_words}

    def crumb(bid):
        r = by_id[bid]
        par = by_id.get(r[3])
        path = pages.get(r[4], "?")
        if par:
            path += " › " + par[2].split("\n")[0][:50]
        return path

    result, lines = {}, []
    for b in links:
        bid = b["db/id"]
        ws, ks = terms[bid]
        scores = defaultdict(float)
        why = defaultdict(set)
        # same page/post: strong. Same repo: strong for a repo link, weak for an
        # issue/PR link (big repos like logseq/logseq are linked everywhere)
        inline = GH_INLINE_RE.match(split_link(b["block/title"])[2])
        for k in ks:
            weight = 15 if k.startswith("repo:") and inline else 100
            for c in key_hits.get(k, ()):
                scores[c] += weight
                why[c].add(k.split(":")[0])
        for w in ws:
            if idf[w] < 4:  # too common to mean anything on its own
                continue
            for c in postings.get(w, ()):
                scores[c] += idf[w]
                why[c].add(w)
        # longer blocks match more words by chance; prefer focused ones
        ranked = sorted(scores, key=lambda c: -scores[c] / (1 + math.log1p(len(by_id[c][2]) / 200)))
        ranked = [c for c in ranked if scores[c] >= min_score][:top]
        text = split_link(new_title(b["block/title"]))[1]
        result[str(bid)] = [{"id": c, "uuid": by_id[c][1], "score": round(scores[c], 1),
                             "why": sorted(why[c]), "page": crumb(c),
                             "title": by_id[c][2][:300]} for c in ranked]
        lines.append(f"\n{bid}  {text[:100]}")
        for c in result[str(bid)]:
            lines.append(f"    {c['score']:>6}  {c['uuid']}  [{','.join(c['why'])[:40]}]  "
                         f"{c['page'][:60]}  ::  {c['title'][:120].replace(chr(10), ' ⏎ ')}")
    out = os.path.join(scratch(root), "related.json")
    with open(out, "w") as f:
        json.dump(result, f, ensure_ascii=False, indent=1)
    print("\n".join(lines))
    print(f"\n{sum(1 for v in result.values() if v)}/{len(links)} link blocks have candidates; "
          f"saved to {out}")


# ---------------------------------------------------------------- apply

def heading_md(level, title, children=()):
    if re.search(r'\[\[|#\w', title):
        sys.exit(f"heading {title!r} would create a page or tag; rename it")
    md = f"- {'#' * level} {title}"
    for c in children:
        md += "\n  - ### " + c
    return md


def cmd_apply(plan_path, dry):
    with open(plan_path) as f:
        plan = json.load(f)
    graph, root = plan["graph"], plan["root"]
    tree = fetch_tree(graph, root)
    root_id = tree["db/id"]
    h2s, top_h3s, blocks = layout(tree)
    current = {b["db/id"]: (b, p) for b, p in blocks}

    planned = [i for g in plan["groups"] for h in g["h3"] for i in h["blocks"]]
    planned += plan.get("ungrouped", [])
    dupes = {i for i in planned if planned.count(i) > 1}
    missing = [i for i in planned if i not in current]
    if dupes or missing:
        sys.exit(f"plan problems: duplicates {sorted(dupes)}, not under root {missing}")
    unmentioned = [i for i in current if i not in planned]
    if unmentioned:
        print(f"not in plan, treated as ungrouped: {unmentioned}")
    ungrouped = plan.get("ungrouped", []) + unmentioned
    ungrouped.sort(key=lambda i: [b["db/id"] for b, _ in blocks].index(i))

    ops, new_md = [], []

    def do(desc, args):
        ops.append(desc)
        if dry:
            return None
        d = run(args, check=False)
        if not d or d.get("status") != "ok":
            print(f"FAILED: {desc}: {d and d.get('error')}", file=sys.stderr)
            return None
        return d["data"]["result"]

    # 1. headings
    def ensure(level, title, parent_id, existing, subs=()):
        if title in existing:
            return existing[title]["db/id"] if level == 3 else existing[title][0]["db/id"]
        md = heading_md(level, title, subs)
        new_md.append(md)
        do(f"create {'#' * level} {title} under {parent_id}",
           ["upsert", "block", "-g", graph, "--target-id", str(parent_id), "--pos", "last-child",
            "--blocks", md, "-o", "json"])
        return None

    for g in plan["groups"]:
        if g.get("h2"):
            have = h2s.get(g["h2"])
            if have:
                for h in g["h3"]:
                    ensure(3, h["title"], have[0]["db/id"], have[1])
            else:
                ensure(2, g["h2"], root_id, {}, [h["title"] for h in g["h3"]])
        else:
            for h in g["h3"]:
                ensure(3, h["title"], root_id, top_h3s)

    # re-read to get the heading ids (dry run: placeholders)
    if not dry:
        tree = fetch_tree(graph, root)
        h2s, top_h3s, _ = layout(tree)

    def h3_id(g, h):
        subs = h2s.get(g["h2"], (None, {}))[1] if g.get("h2") else top_h3s
        if h["title"] in subs:
            return subs[h["title"]]["db/id"]
        return f"<{h['title']}>"  # dry run: not created yet

    # 2. moves (skip blocks already in place)
    moved = 0
    for g in plan["groups"]:
        for h in g["h3"]:
            target = h3_id(g, h)
            for i in h["blocks"]:
                if current[i][1].get("db/id") == target:
                    continue
                moved += 1
                do(f"move {i} -> {target}", ["upsert", "block", "-g", graph, "--id", str(i),
                                              "--target-id", str(target), "--pos", "last-child",
                                              "-o", "json"])
    for i in ungrouped:  # always re-appended, so they end up after the headings
        moved += 1
        do(f"move {i} -> end of root", ["upsert", "block", "-g", graph, "--id", str(i),
                                         "--target-id", str(root_id), "--pos", "last-child",
                                         "-o", "json"])

    # 3. link text + gfw
    retitled = 0
    overrides = plan.get("titles", {})
    for i, (b, _) in current.items():
        t = b.get("block/title", "")
        nt = new_title(t)
        if str(i) in overrides:
            prefix, _, url, rest = split_link(nt)
            nt = f"{prefix}[{overrides[str(i)]}]({url}){rest}"
        if nt != t:
            retitled += 1
            new_md.append("- " + nt.replace("\n", "\n  "))
            ops.append(f"retitle {i}: {nt[:100]!r}")
            if not dry:
                d = run(["upsert", "block", "-g", graph, "--id", str(i), "--content", nt,
                         "-o", "json"], check=False)
                if not d or d.get("status") != "ok":
                    print(f"FAILED: retitle {i}: {d and d.get('error')}", file=sys.stderr)

    # 4. Related:
    added = 0
    for i, uuids in plan.get("related", {}).items():
        b = current[int(i)][0]
        have = set(related_refs(b))
        todo = [u for u in uuids if u not in have]
        if not todo:
            continue
        added += len(todo)
        refs = "\n".join(f"- [[{u}]]" for u in todo)
        rc = related_child(b)
        if rc:
            target, md = rc["db/id"], refs
        else:
            target, md = int(i), f"- {RELATED}\n" + "\n".join("  " + l for l in refs.split("\n"))
        new_md.append(md)
        do(f"related {i}: +{len(todo)}", ["upsert", "block", "-g", graph, "--target-id",
                                           str(target), "--pos", "last-child", "--blocks", md,
                                           "-o", "json"])

    print("\n".join(ops) if dry else f"{len(ops)} ops done")
    print(f"\nheadings created: {sum(1 for o in ops if o.startswith('create'))}, moves: {moved}, "
          f"retitled: {retitled}, related refs added: {added}")
    if dry and new_md:
        d = run(["upsert", "block", "-g", graph, "--target-uuid", root, "--pos", "last-child",
                 "--dry-run", "--output", "json", "--blocks", "\n".join(new_md)], check=False)
        pages = d and d.get("data", {}).get("would-create-pages")
        print(f"would-create-pages: {pages if d else 'dry run failed: ' + str(d)}")


def main():
    a = sys.argv[1:]
    flags = {x for x in a if x.startswith("--")}
    a = [x for x in a if not x.startswith("--")]
    top, min_score = 6, 12
    for fl in list(flags):
        if fl.startswith("--top="):
            top = int(fl.split("=", 1)[1])
        if fl.startswith("--min="):
            min_score = float(fl.split("=", 1)[1])
    if a[:1] == ["dump"] and len(a) == 3:
        cmd_dump(a[1], a[2])
    elif a[:1] == ["index"] and len(a) == 2:
        cmd_index(a[1], "--refresh" in flags)
    elif a[:1] == ["related"] and len(a) == 3:
        cmd_related(a[1], a[2], top, min_score)
    elif a[:1] == ["apply"] and len(a) == 2:
        cmd_apply(a[1], "--dry-run" in flags)
    else:
        sys.exit(__doc__.split("\n\n")[1])


if __name__ == "__main__":
    main()
