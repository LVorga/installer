#!/usr/bin/env bash
# Installation du wiki LVorga — macOS / Linux.
# Usage : curl -fsSL https://raw.githubusercontent.com/LVorga/installer/main/installer.sh | bash -s <prenom>
set -euo pipefail
ORG=LVorga

slug() {
  printf '%s' "$1" | sed 's/^ *//;s/ *$//' \
    | iconv -f UTF-8 -t ASCII//TRANSLIT 2>/dev/null \
    | tr '[:upper:]' '[:lower:]' | sed -E "s/[ ']+/-/g; s/[^a-z0-9-]//g; s/-+/-/g; s/^-//; s/-$//"
}
[ "${1:-}" = "--source-only" ] && return 0 2>/dev/null

etape() { printf '\n\033[1m▶ %s\033[0m\n' "$1"; }
PRENOM="${1:-}"
[ -z "$PRENOM" ] && { read -r -p "Ton prénom : " PRENOM < /dev/tty; }
NOM="wiki-$(slug "$PRENOM")"; DOSSIER="$HOME/wiki"

etape "Vérification des outils"
installer() {  # $1 = commande, $2 = paquet brew, $3 = paquet apt
  command -v "$1" >/dev/null && return 0
  if command -v brew >/dev/null; then brew install "$2"
  elif command -v apt-get >/dev/null; then sudo apt-get update -qq && sudo apt-get install -y "$3"
  else echo "Installe « $1 » puis relance cette commande."; exit 1; fi
}
installer git git git
installer gh gh gh
command -v claude >/dev/null || curl -fsSL https://claude.ai/install.sh | bash
export PATH="$HOME/.local/bin:$PATH"

etape "Connexion à GitHub (une page va s'ouvrir dans ton navigateur : clique sur « Authorize »)"
gh auth status >/dev/null 2>&1 || gh auth login --hostname github.com --git-protocol https --web
gh auth setup-git

etape "Accès à l'espace de l'équipe"
gh api -X PATCH "user/memberships/orgs/$ORG" -f state=active >/dev/null 2>&1 || true
for id in $(gh api user/repository_invitations --jq ".[] | select(.repository.owner.login==\"$ORG\") | .id" 2>/dev/null); do
  gh api -X PATCH "user/repository_invitations/$id" >/dev/null 2>&1 || true
done
if ! gh repo view "$ORG/$NOM" >/dev/null 2>&1; then
  echo "Je ne trouve pas ton wiki ($ORG/$NOM). As-tu accepté l'invitation reçue par e-mail de GitHub ?"
  echo "Accepte-la puis relance cette commande. Sinon, préviens Lorenzo."; exit 1
fi

etape "Installation de ton wiki dans $DOSSIER"
if [ -d "$DOSSIER/.git" ]; then git -C "$DOSSIER" pull -q --rebase --autostash || true
else gh repo clone "$ORG/$NOM" "$DOSSIER" -- -q; fi

# Mises à jour automatiques des compétences de l'équipe (réglage utilisateur de Claude Code).
python3 - "$HOME/.claude/settings.json" <<'PY' 2>/dev/null || true
import json, sys, os
p = sys.argv[1]
d = json.load(open(p)) if os.path.exists(p) else {}
d.setdefault("extraKnownMarketplaces", {})["lvorga"] = {"source": {"source": "github", "repo": "LVorga/marketplace"}, "autoUpdate": True}
d.setdefault("env", {})["CLAUDE_CODE_PLUGIN_PREFER_HTTPS"] = "1"
os.makedirs(os.path.dirname(p), exist_ok=True)
json.dump(d, open(p, "w"), indent=2)
PY

printf '\n\033[1m✔ C'"'"'est prêt.\033[0m\nPour travailler : ouvre un terminal, tape  cd ~/wiki && claude\n'
printf 'La première fois, réponds « oui » quand Claude demande de faire confiance au dossier et d'"'"'installer les compétences de l'"'"'équipe.\n'
