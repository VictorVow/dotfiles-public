"""logseq_links.py — shared link helpers for the Logseq skills.

Import it from another skill's script with:

    sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../logseq-add-md-to-blocks/scripts"))
    from logseq_links import linktext, relink, gfw_block

- linktext(title, url): the link text for a Markdown link, following the
  title rules in logseq-add-md-to-blocks step 3 (site suffixes dropped, repo
  links titled with the repo name, issue/PR titles without the
  "· Pull Request \\#N · owner/repo" tail or "[Bug]:" prefixes, `#` escaped).
- relink(block): rewrite the block's leading `[text](url)` with linktext.
- gfw_block(block): add the Git Forge Watcher macro to a block that starts with
  a GitHub link (no-op if it already has one).

Used by logseq-md-to-blocks.py, logseq-enrich-blocks and
process-firefox-synced-tabs.
"""

import re
from urllib.parse import parse_qs, quote, unquote_plus, urlparse

GH_LEAD_RE = re.compile(
    r'^(#{1,6} )?(?:\[[^\]]*\]\(|<)?(https://github\.com/[\w.-]+/[\w.-]+[^\s)>]*)')
# Links the plugin renders as an inline (non-repo) widget.
GH_INLINE_RE = re.compile(
    r'^https://github\.com/[^/]+/[^/]+/(?:issues/\d+|pull/\d+|tree/[^/?#]+)')
GH_REPO_RE = re.compile(r'^https://github\.com/([\w.-]+)/([\w.-]+?)(?:\.git)?/?(?:[?#].*)?$')
# "<title> by <user> · Pull Request #N · owner/repo", "<title> · Issue #N · owner/repo"
GH_ITEM_TAIL_RE = re.compile(
    r'(?:\s+by\s+\S+)?\s+·\s+(?:Pull Request|Issue|Discussion)\s+#\d+\s+·\s+[\w.-]+/[\w.-]+\s*$')
# "[Bug]: ", also "[Bug): " once the "]" was already replaced
TEMPLATE_PREFIX_RE = re.compile(r'^\[[^\])]*[\])]:?\s*')
# "<mod> at <Game> Nexus - Mods and community"
NEXUS_RE = re.compile(r'\s+at\s+.+?\s+Nexus\s+-\s+Mods and community$')
GFW_MACRO = '{{renderer :gfw, '

# suffixes that identify the site, not the page — strip " - X"/" | X" tails
_SITE_TAILS = re.compile(
    r"\s*(?:\||-|·|—|–)\s*(?:"
    r"GitHub|GitLab|Brave Search|Google Search|Hacker News|YouTube|"
    r"Reddit|Wikipedia|Stack Overflow|Stack Exchange|Amazon|Medium|"
    r"PCGamingWiki PCGW(?: - bugs.*)?|Nexus [Mm]ods|Royal Road|BBC|Reuters|"
    r"AlternativeTo|Product Hunt|Wikibooks|DevDocs|MDN Web Docs"
    r")[^-|·—–]*$")


ERROR_TITLES = {
    "error", "address not found", "the connection has timed out", "problem loading page",
    "server not found", "page not found", "looks like there’s a problem with your internet connection",
    "looks like there's a problem with your internet connection",
}


def _title_from_url(p):
    """A readable title from the URL itself: a search query, or a slug."""
    qs = parse_qs(p.query)
    for key in ("q", "query", "text", "search"):
        if key in qs and qs[key][0]:
            return unquote_plus(qs[key][0])
    m = re.match(r'^/r/([^/]+)/comments/[^/]+/([^/]+)', p.path)  # reddit + frontends
    if m:
        return m.group(2).replace("_", " ").capitalize() + " - r/" + m.group(1)
    m = re.match(r'^/(?:t|d)/(?:\d+-)?([a-z0-9-]*[a-z][a-z0-9-]*)', p.path)  # Discourse, Flarum
    if m:
        return m.group(1).replace("-", " ").capitalize()
    return ""


def linktext(title, url):
    """Title for the markdown link, cleaned per logseq-add-md-to-blocks rules."""
    t = (title or "").strip().replace("\\#", "#")
    repo = GH_REPO_RE.match(url or "")
    if repo:
        # repo name, keeping the title's case if it starts with owner/repo
        full = f'{repo.group(1)}/{repo.group(2)}'
        if t.lower().startswith(full.lower()):
            t = t[len(repo.group(1)) + 1:len(full)]
        elif t.lower() != repo.group(2).lower():  # already cleaned: keep its case
            t = repo.group(2)
    else:
        t = GH_ITEM_TAIL_RE.sub("", t)
        if " | " in t:
            t = t.rsplit(" | ", 1)[0].strip()
        if t.startswith("GitHub - "):
            t = t[len("GitHub - "):]
        t = NEXUS_RE.sub("", t)
        prev = None
        while prev != t:
            prev = t
            t = _SITE_TAILS.sub("", t).strip()
        if "github.com/" in (url or ""):
            t = TEMPLATE_PREFIX_RE.sub("", t)
    p = urlparse(url or "")
    # no real title: empty, a browser error page, or a URL fragment that
    # Firefox used because the page never loaded
    if (not t or t.lower() in ERROR_TITLES
            or (" " not in t and re.match(r'^[\w-]+(\.[\w-]+)+/', t))):
        t = _title_from_url(p) or (t if t.lower() not in ERROR_TITLES else "") \
            or p.netloc + (p.path[:40] if p.path != "/" else "")
    # amazon search links: use the k= param
    if "amazon." in p.netloc and p.path in ("/s", "/gp/search"):
        k = parse_qs(p.query).get("k")
        if k: t = "Amazon: " + unquote_plus(k[0])
    t = t.replace("#", "\\#")
    if t.startswith("[["): t = t[2:]
    t = t.replace("]", ")")
    return t


def split_link(block):
    """(prefix, text, url, rest) for a block whose first line starts with a
    Markdown link (after any heading #s and gfw macro), else None."""
    m = re.match(r'^((?:#{1,6} )?(?:\{\{renderer :gfw, [^}]*\}\} )?)\[', block)
    if not m:
        return None
    end = block.find('](http', m.end())
    if end < 0 or '\n' in block[m.end():end]:
        return None
    url_m = re.match(r'\]\((https?://[^\s)]*(?:\([^\s)]*\)[^\s)]*)*)\)', block[end:])
    if not url_m:
        return None
    close = end + url_m.end()
    return m.group(1), block[m.end():end], url_m.group(1), block[close:]


def relink(block):
    """Rewrite the block's leading link text with linktext()."""
    parts = split_link(block)
    if not parts:
        return block
    prefix, text, url, rest = parts
    return f'{prefix}[{linktext(text, url)}]({url}){rest}'


def gfw_block(block):
    """Add a Git Forge Watcher widget to a block that starts with a GitHub link.

    Repo links get the macro on the block's second line; issue, pull request
    and branch links get it at the start of the first line, after any heading
    #s, followed by one space."""
    if GFW_MACRO in block:
        return block
    m = GH_LEAD_RE.match(block)
    if not m:
        return block
    macro = GFW_MACRO + quote(m.group(2), safe='') + '}}'
    if GH_INLINE_RE.match(m.group(2)):
        prefix = m.group(1) or ''
        return prefix + macro + ' ' + block[len(prefix):]
    return block + '\n' + macro
