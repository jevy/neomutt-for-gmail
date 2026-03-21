query="${1:-}"

# Require a query — fzf --filter="" returns everything
if [ -z "$query" ] || [ -z "${query// /}" ]; then
  echo "Type a name or email to search"
  exit 1
fi

# Header line (required by mutt query_command protocol)
echo "Searching contacts..."

# Collect all contacts from both sources, deduplicate, then fuzzy-match with fzf.
# Dumps all contacts rather than pre-filtering so fzf can do proper fuzzy matching
# (e.g. "ashm" matches "Ashley Maltais").
# Notmuch comes FIRST so dedup keeps the entry with the prevalence count;
# goobook-only contacts (not in email history) still appear after.
{
  # 1. Email history via notmuch address, sorted by message count (prevalence)
  # Using sender-only (cached in DB, fast) — recipients require opening
  # every message file and can take 10+ seconds on large mailboxes.
  notmuch address --output=sender --output=count \
    --deduplicate=address "*" 2>/dev/null \
    | sort -t'	' -k1 -nr \
    | awk -F '	' '{
      addr = $2; count = $1
      # Parse "Name <email>" format
      if (match(addr, /<[^>]+>/)) {
        email = substr(addr, RSTART+1, RLENGTH-2)
        name = substr(addr, 1, RSTART-1)
        gsub(/^[ \t]+|[ \t]+$/, "", name)
      } else {
        email = addr
        name = ""
      }
      gsub(/^[ \t]+|[ \t]+$/, "", email)
      if (email != "") print email "\t" name "\t[notmuch:" count "]"
    }'

  # 2. Google Contacts via goobook (silently skip if not authenticated)
  # Filter out "(group)" lines which contain entire contact groups as one entry
  goobook query "" 2>/dev/null | grep -v "(group)" || true
} | awk -F '\t' 'NF && $1 != "" && !seen[tolower($1)]++' \
  | fzf --filter="$query" -d '\t' --nth=1,2 \
  | head -50 \
  | awk -F '\t' '{
    # fzf narrows to the top ~50 fuzzy matches; now re-sort by email
    # prevalence so contacts you email most appear first within that set.
    # Extract notmuch count from 3rd column (e.g. "[notmuch:42]").
    # Goobook-only entries get score 0.
    score = 0
    if (match($3, /\[notmuch:([0-9]+)\]/, m)) score = m[1]
    print score "\t" $0
  }' \
  | sort -t'	' -k1 -nr \
  | head -20 \
  | cut -f2-  # strip the score column before passing to neomutt
