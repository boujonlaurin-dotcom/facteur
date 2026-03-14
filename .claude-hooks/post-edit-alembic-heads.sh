#!/bin/bash
# Hook: PostToolUse (Edit/Write)
# Vérifie qu'il n'y a qu'un seul Alembic head après création/modification de migration

file=$(echo "$CLAUDE_TOOL_INPUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('file_path',''))" 2>/dev/null)

# Ne s'applique qu'aux fichiers dans alembic/versions/
if [[ "$file" != *"alembic/versions"*".py"* ]]; then
  exit 0
fi

heads=$(python3 -c "
import re; from pathlib import Path
d = Path('packages/api/alembic/versions')
if not d.exists():
    print('0')
    exit()
revs={}; refs=set()
for f in d.glob('*.py'):
    c=f.read_text()
    r=re.search(r\"^revision\s*(?::\s*str)?\s*=\s*['\\\"]([^'\\\"]+)['\\\"]\", c, re.M)
    dn=re.search(r\"^down_revision\s*(?:[^=]+)?\s*=\s*(.+?)$\", c, re.M|re.S)
    if r:
        revs[r.group(1)]=[]; refs.update(re.findall(r\"['\\\"]([^'\\\"]+)['\\\"]\", dn.group(1)) if dn else [])
h=[x for x in revs if x not in refs]
print(len(h))
" 2>/dev/null)

if [ -z "$heads" ] || [ "$heads" = "0" ]; then
  exit 0
fi

if [ "$heads" != "1" ]; then
  echo "ALEMBIC MULTI-HEAD DÉTECTÉ ($heads heads) !"
  echo ""
  echo "→ La nouvelle migration doit merger les heads existants."
  echo "→ Utiliser down_revision = (head1, head2, ...) pour fusionner."
  echo ""
  # Afficher les heads pour debug
  python3 -c "
import re; from pathlib import Path
d = Path('packages/api/alembic/versions'); revs={}; refs=set()
for f in d.glob('*.py'):
    c=f.read_text()
    r=re.search(r\"^revision\s*(?::\s*str)?\s*=\s*['\\\"]([^'\\\"]+)['\\\"]\", c, re.M)
    dn=re.search(r\"^down_revision\s*(?:[^=]+)?\s*=\s*(.+?)$\", c, re.M|re.S)
    if r:
        revs[r.group(1)]=[]; refs.update(re.findall(r\"['\\\"]([^'\\\"]+)['\\\"]\", dn.group(1)) if dn else [])
print('HEADS:', [h for h in revs if h not in refs])
" 2>/dev/null
  exit 1
fi

exit 0
