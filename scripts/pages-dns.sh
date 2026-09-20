#!/bin/bash
# Points a Cloudflare-hosted domain at GitHub Pages. Idempotent: creates or updates
# the apex A/AAAA set, the www CNAME and (optionally) the Pages verification TXT.
#
#   scripts/pages-dns.sh                      # apply for backspacer.dev
#   scripts/pages-dns.sh --check              # print what exists, change nothing
#   VERIFY=<code> scripts/pages-dns.sh        # also add _github-pages-challenge-<user> TXT
#
# Token: an API token scoped to  Zone › DNS › Edit  on this zone only, stored in
# $CF_TOKEN_FILE (default ~/.config/cloudflare/backspacer.token, mode 0600). It is
# read into a variable and sent as a header; it is never echoed or logged.
#
# Records are DNS-only (not proxied): GitHub issues the Let's Encrypt certificate
# for the domain itself, which needs to see the A records, and "Enforce HTTPS" in
# the Pages settings then works. .dev is on the HSTS preload list, so HTTPS must.
set -euo pipefail

DOMAIN="${DOMAIN:-backspacer.dev}"
GH_USER="${GH_USER:-anton-g-kulikov}"
CF_TOKEN_FILE="${CF_TOKEN_FILE:-$HOME/.config/cloudflare/backspacer.token}"
API="https://api.cloudflare.com/client/v4"
CHECK=0; [ "${1:-}" = "--check" ] && CHECK=1

# GitHub Pages anycast addresses — https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site
A_RECORDS=(185.199.108.153 185.199.109.153 185.199.110.153 185.199.111.153)
AAAA_RECORDS=(2606:50c0:8000::153 2606:50c0:8001::153 2606:50c0:8002::153 2606:50c0:8003::153)

[ -r "$CF_TOKEN_FILE" ] || { echo "no token at $CF_TOKEN_FILE (chmod 600 a file holding the API token)"; exit 1; }
[ "$(stat -f %Lp "$CF_TOKEN_FILE")" = "600" ] || { echo "$CF_TOKEN_FILE must be mode 600"; exit 1; }
TOKEN="$(tr -d '[:space:]' < "$CF_TOKEN_FILE")"

cf() { # cf METHOD PATH [JSON]
  curl -sS -X "$1" "$API$2" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" ${3:+--data "$3"}
}
ok() { python3 -c 'import json,sys; d=json.load(sys.stdin); sys.exit(0 if d.get("success") else 1) or print(json.dumps(d["result"]))' ; }

echo "▸ token"
cf GET /user/tokens/verify | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["success"], d; print("  " + d["result"]["status"])'

echo "▸ zone $DOMAIN"
ZONE=$(cf GET "/zones?name=$DOMAIN" | python3 -c 'import json,sys; r=json.load(sys.stdin)["result"]; print(r[0]["id"] if r else "")')
[ -n "$ZONE" ] || { echo "  zone not found — is the domain in this Cloudflare account and the token scoped to it?"; exit 1; }
echo "  $ZONE"

RECORDS=$(cf GET "/zones/$ZONE/dns_records?per_page=200")

# upsert TYPE NAME CONTENT — one record per (type, name, content) for A/AAAA; one per (type, name) for CNAME/TXT
upsert() {
  local type="$1" name="$2" content="$3" id
  if [ "$type" = A ] || [ "$type" = AAAA ]; then
    id=$(printf '%s' "$RECORDS" | python3 -c "import json,sys; r=[x for x in json.load(sys.stdin)['result'] if x['type']=='$type' and x['name']=='$name' and x['content']=='$content']; print(r[0]['id'] if r else '')")
  else
    id=$(printf '%s' "$RECORDS" | python3 -c "import json,sys; r=[x for x in json.load(sys.stdin)['result'] if x['type']=='$type' and x['name']=='$name']; print(r[0]['id'] if r else '')")
  fi
  local body; body=$(python3 -c "import json; print(json.dumps({'type':'$type','name':'$name','content':'$content','ttl':1,'proxied':False}))")
  if [ "$CHECK" = 1 ]; then printf '  %-5s %-45s %-28s %s\n' "$type" "$name" "$content" "${id:+present}${id:-MISSING}"; return; fi
  if [ -n "$id" ]; then cf PATCH "/zones/$ZONE/dns_records/$id" "$body" >/dev/null && printf '  = %-5s %s → %s\n' "$type" "$name" "$content"
  else cf POST "/zones/$ZONE/dns_records" "$body" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["success"], d["errors"]' && printf '  + %-5s %s → %s\n' "$type" "$name" "$content"; fi
}

echo "▸ records (DNS-only)"
for ip in "${A_RECORDS[@]}";    do upsert A    "$DOMAIN" "$ip"; done
for ip in "${AAAA_RECORDS[@]}"; do upsert AAAA "$DOMAIN" "$ip"; done
upsert CNAME "www.$DOMAIN" "$GH_USER.github.io"
[ -n "${VERIFY:-}" ] && upsert TXT "_github-pages-challenge-$GH_USER.$DOMAIN" "$VERIFY"

# Anything else at the apex or www that would shadow the Pages records (stale A, a parking CNAME).
printf '%s' "$RECORDS" | python3 -c "
import json,sys
want={('A','$DOMAIN'),('AAAA','$DOMAIN'),('CNAME','www.$DOMAIN')}
odd=[x for x in json.load(sys.stdin)['result'] if x['name'] in ('$DOMAIN','www.$DOMAIN') and (x['type'],x['name']) not in want]
for x in odd: print('  ! unexpected', x['type'], x['name'], '→', x['content'], '(proxied)' if x.get('proxied') else '')
" 2>/dev/null || true

[ "$CHECK" = 1 ] && exit 0
echo "▸ resolver"
for i in 1 2 3 4 5 6; do
  if dig +short A "$DOMAIN" @1.1.1.1 | grep -q 185.199; then dig +short A "$DOMAIN" @1.1.1.1 | sed 's/^/  /'; break; fi
  sleep 5
done
echo "✓ $DOMAIN → GitHub Pages. Next: set the custom domain on the repo (Settings → Pages, or"
echo "  gh api -X PUT repos/$GH_USER/<repo>/pages -f cname=$DOMAIN -F https_enforced=true) and wait for the certificate."
