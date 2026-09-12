#!/bin/zsh
# tasks_note.sh — Milad's task inbox is a shared Apple Note ("El Dorado Tasks").
# Reads it from the local Notes app (same iCloud account), prints it as text, and
# diffs against the last snapshot in game/.gate/tasks_seen.txt so a session can
# tell NEW items from ones already worked. Machine-local by nature (osascript).
# Usage: game/tools/tasks_note.sh            # print + diff, update the snapshot
#        game/tools/tasks_note.sh --peek     # print + diff, leave the snapshot alone
HERE=${0:a:h:h}
SNAP="$HERE/.gate/tasks_seen.txt"
mkdir -p "$HERE/.gate"
RAW=$(perl -e 'alarm 30; exec @ARGV' osascript -e 'tell application "Notes" to get body of (first note whose name contains "El Dorado Tasks")' 2>&1)
if [[ $? -ne 0 || "$RAW" == *"error"* ]]; then
  echo "TASKS: could not read the note from Notes.app — $RAW"
  echo "TASKS: fallback is the share link; it needs 'anyone with the link' to be readable without sign-in."
  exit 2
fi
TEXT=$(printf '%s' "$RAW" | python3 -c '
import sys,re,html
s=sys.stdin.read()
s=re.sub(r"<br\s*/?>","\n",s); s=re.sub(r"</(div|p|li|h\d|ul|ol|tr)>","\n",s); s=re.sub(r"<li[^>]*>","- ",s)
t=html.unescape(re.sub(r"<[^>]+>","",s))
print("\n".join(l.rstrip() for l in t.splitlines() if l.strip()))')
echo "=== El Dorado Tasks (Notes.app, $(date '+%Y-%m-%d %H:%M')) ==="
printf '%s\n' "$TEXT"
echo "=== new since last snapshot ==="
if [[ -f "$SNAP" ]]; then
  NEW=$(diff <(printf '%s\n' "$TEXT") "$SNAP" | grep '^<' | sed 's/^< //')
  if [[ -z "$NEW" ]]; then echo "(none)"; else printf '%s\n' "$NEW"; fi
else
  echo "(no snapshot yet — everything above is new)"
fi
[[ "$1" == "--peek" ]] || printf '%s\n' "$TEXT" > "$SNAP"
