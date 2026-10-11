#!/usr/bin/env bash
# Installation du wiki LVorga — macOS / Linux.
# Usage : curl -fsSL https://raw.githubusercontent.com/LVorga/installer/main/installer.sh | bash -s <prenom>
set -euo pipefail
ORG=LVorga

slug() {  # même règle dans installer/installer.sh, installer/installer.ps1 et admin/commun.sh
  perl -CSA -MUnicode::Normalize -e '$_ = lc $ARGV[0]; s/^\s+|\s+$//g;
    s/\x{153}/oe/g; s/\x{e6}/ae/g; s/\x{f8}/o/g; s/\x{df}/ss/g; s/\x{142}/l/g;
    $_ = NFD($_); s/\pM//g; s/[\s\x{27}\x{2019}]+/-/g; s/[^a-z0-9-]//g; s/-+/-/g; s/^-|-$//g; print' -- "$1"
}
[ "${1:-}" = "--source-only" ] && return 0 2>/dev/null

# Tout le script est dans main() : un téléchargement interrompu n'exécute rien à moitié.
main() {
  etape() { printf '\n\033[1m▶ %s\033[0m\n' "$1"; }
  local PRENOM="${1:-}" NOM DOSSIER="$HOME/wiki" login uid
  [ -z "$PRENOM" ] && read -r -p "Ton prénom : " PRENOM < /dev/tty
  NOM="wiki-$(slug "$PRENOM")"
  [ "$NOM" = "wiki-" ] && { echo "Prénom non reconnu. Relance la commande en ajoutant ton prénom sans accents à la fin."; exit 1; }

  etape "Vérification des outils"
  if [ "$(uname)" = Darwin ] && ! xcode-select -p >/dev/null 2>&1; then
    xcode-select --install 2>/dev/null || true
    echo "Une fenêtre propose d'installer les « outils de ligne de commande » : clique sur Installer, attends la fin, puis relance cette commande."
    exit 1
  fi
  installer_paquet git git git
  command -v gh >/dev/null || installer_gh
  command -v claude >/dev/null || curl -fsSL https://claude.ai/install.sh | bash
  export PATH="$HOME/.local/bin:$PATH"

  etape "Connexion à GitHub (une page va s'ouvrir dans ton navigateur : clique sur « Authorize »)"
  gh auth status >/dev/null 2>&1 || gh auth login --hostname github.com --git-protocol https --web < /dev/tty
  gh auth setup-git

  etape "Accès à l'espace de l'équipe"
  gh api -X PATCH "user/memberships/orgs/$ORG" -f state=active >/dev/null 2>&1 || true
  for id in $(gh api user/repository_invitations --jq ".[] | select(.repository.owner.login==\"$ORG\") | .id" 2>/dev/null); do
    gh api -X PATCH "user/repository_invitations/$id" >/dev/null 2>&1 || true
  done
  if ! gh repo view "$ORG/$NOM" >/dev/null 2>&1; then
    echo "Je ne trouve pas ton wiki ($ORG/$NOM). Vérifie que tu es connecté avec le bon compte GitHub, sinon préviens Lorenzo."; exit 1
  fi
  if ! gh repo view "$ORG/marketplace" >/dev/null 2>&1; then
    echo "Ton accès aux compétences de l'équipe n'est pas encore ouvert. Préviens Lorenzo, puis relance cette commande."; exit 1
  fi

  etape "Installation de ton wiki dans $DOSSIER"
  if [ -d "$DOSSIER/.git" ]; then git -C "$DOSSIER" pull -q --rebase --autostash || true
  else gh repo clone "$ORG/$NOM" "$DOSSIER" -- -q; fi
  login=$(gh api user --jq .login); uid=$(gh api user --jq .id)
  git -C "$DOSSIER" config user.name "$PRENOM"
  git -C "$DOSSIER" config user.email "$uid+$login@users.noreply.github.com"

  # Mises à jour automatiques des compétences de l'équipe (réglage utilisateur de Claude Code).
  if ! python3 - "$HOME/.claude/settings.json" <<'PY2' 2>/dev/null; then
import json, sys, os
p = sys.argv[1]
d = json.load(open(p)) if os.path.exists(p) else {}
d.setdefault("extraKnownMarketplaces", {})["lvorga"] = {"source": {"source": "github", "repo": "LVorga/marketplace"}, "autoUpdate": True}
d.setdefault("env", {})["CLAUDE_CODE_PLUGIN_PREFER_HTTPS"] = "1"
os.makedirs(os.path.dirname(p), exist_ok=True)
json.dump(d, open(p, "w"), indent=2)
PY2
    echo "(Info pour Lorenzo : mise à jour automatique des compétences non réglée sur ce poste.)"
  fi

  printf '\n\033[1m✔ C'"'"'est prêt.\033[0m\nPour travailler : ouvre un terminal, tape  cd ~/wiki && claude\n'
  printf 'La première fois, réponds « oui » quand Claude demande de faire confiance au dossier.\n'
}

installer_paquet() {  # $1 = commande, $2 = paquet brew, $3 = paquet apt
  command -v "$1" >/dev/null && return 0
  if command -v brew >/dev/null; then brew install "$2"
  elif command -v apt-get >/dev/null; then sudo apt-get update -qq && sudo apt-get install -y "$3" < /dev/tty
  else echo "Installe « $1 » puis relance cette commande (ou préviens Lorenzo)."; exit 1; fi
}

installer_gh() {  # GitHub CLI : paquet si possible, sinon binaire officiel dans ~/.local/bin
  if command -v brew >/dev/null || command -v apt-get >/dev/null; then installer_paquet gh gh gh; return; fi
  local motif t url
  case "$(uname)-$(uname -m)" in
    Darwin-arm64) motif='macOS_arm64\.zip' ;;
    Darwin-*)     motif='macOS_amd64\.zip' ;;
    *-aarch64|*-arm64) motif='linux_arm64\.tar\.gz' ;;
    *)            motif='linux_amd64\.tar\.gz' ;;
  esac
  url=$(curl -fsSL https://api.github.com/repos/cli/cli/releases/latest | grep -o "https://[^\"]*$motif" | head -1)
  [ -n "$url" ] || { echo "Impossible de télécharger GitHub CLI. Préviens Lorenzo."; exit 1; }
  t=$(mktemp -d); curl -fsSL "$url" -o "$t/gh.archive"
  case "$url" in *.zip) unzip -q "$t/gh.archive" -d "$t" ;; *) tar -xzf "$t/gh.archive" -C "$t" ;; esac
  mkdir -p "$HOME/.local/bin"; cp "$t"/gh_*/bin/gh "$HOME/.local/bin/gh"; rm -rf "$t"
  export PATH="$HOME/.local/bin:$PATH"
}

main "$@"
