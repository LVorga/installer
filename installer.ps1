# Installation du wiki LVorga — Windows.
# Usage (PowerShell) : irm https://raw.githubusercontent.com/LVorga/installer/main/installer.ps1 | iex
$ErrorActionPreference = 'Stop'
$Org = 'LVorga'

function Get-Slug([string]$s) {  # même règle que installer.sh et admin/commun.sh
  $n = $s.Trim().ToLower()
  $n = $n.Replace([string][char]0x153,'oe').Replace([string][char]0xE6,'ae').Replace([string][char]0xF8,'o').Replace([string][char]0xDF,'ss').Replace([string][char]0x142,'l')
  $n = $n.Normalize([Text.NormalizationForm]::FormD)
  $n = -join ($n.ToCharArray() | Where-Object { [Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark' })
  $n = $n -replace "[\s'$([char]0x2019)]+", '-' -replace '[^a-z0-9-]', '' -replace '-+', '-'
  return $n.Trim('-')
}
function Etape($t) { Write-Host "`n> $t" -ForegroundColor Cyan }
function Rafraichir-Path { $env:Path = [Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [Environment]::GetEnvironmentVariable('Path','User') }

$Prenom = Read-Host 'Ton prénom'
$Nom = "wiki-$(Get-Slug $Prenom)"; $Dossier = Join-Path $HOME 'wiki'
if ($Nom -eq 'wiki-') { Write-Host 'Prénom non reconnu : relance et tape ton prénom sans accents.' -ForegroundColor Yellow; return }

Etape 'Vérification des outils'
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { winget install --id Git.Git -e --silent --accept-source-agreements --accept-package-agreements }
if (-not (Get-Command gh  -ErrorAction SilentlyContinue)) { winget install --id GitHub.cli -e --silent --accept-source-agreements --accept-package-agreements }
Rafraichir-Path
if (-not (Get-Command claude -ErrorAction SilentlyContinue)) { Invoke-RestMethod https://claude.ai/install.ps1 | Invoke-Expression; Rafraichir-Path }

foreach ($c in 'git','gh','claude') {
  if (-not (Get-Command $c -ErrorAction SilentlyContinue)) {
    Write-Host "L'outil « $c » n'a pas pu être installé. Ferme PowerShell, rouvre-le et relance la commande. Si ça recommence, préviens Lorenzo." -ForegroundColor Yellow
    return
  }
}

$ErrorActionPreference = 'Continue'   # gh renvoie des codes non nuls attendus (non connecté, dépôt absent)
Etape "Connexion à GitHub (une page va s'ouvrir : clique sur « Authorize »)"
gh auth status *> $null
if ($LASTEXITCODE -ne 0) { gh auth login --hostname github.com --git-protocol https --web }
gh auth setup-git

Etape "Accès à l'espace de l'équipe"
gh api -X PATCH "user/memberships/orgs/$Org" -f state=active *> $null
# Filtrage en PowerShell (et non --jq) : PowerShell 5 abîme les guillemets passés aux programmes natifs.
(gh api user/repository_invitations | ConvertFrom-Json) | Where-Object { $_.repository.owner.login -eq $Org } |
  ForEach-Object { gh api -X PATCH "user/repository_invitations/$($_.id)" *> $null }
gh repo view "$Org/$Nom" *> $null
if ($LASTEXITCODE -ne 0) {
  Write-Host "Je ne trouve pas ton wiki ($Org/$Nom). Vérifie que tu es connecté avec le bon compte GitHub, sinon préviens Lorenzo." -ForegroundColor Yellow
  return
}
gh repo view "$Org/marketplace" *> $null
if ($LASTEXITCODE -ne 0) {
  Write-Host "Ton accès aux compétences de l'équipe n'est pas encore ouvert. Préviens Lorenzo, puis relance la commande." -ForegroundColor Yellow
  return
}

Etape "Installation de ton wiki dans $Dossier"
if (Test-Path (Join-Path $Dossier '.git')) { git -C $Dossier pull -q --rebase --autostash }
else { gh repo clone "$Org/$Nom" $Dossier -- -q }
if (($LASTEXITCODE -ne 0) -or -not (Test-Path (Join-Path $Dossier '.git'))) {
  Write-Host "L'installation du wiki dans $Dossier a échoué. Vérifie ta connexion et relance la commande. Si ça recommence, préviens Lorenzo." -ForegroundColor Yellow
  return
}
$moi = gh api user | ConvertFrom-Json
git -C $Dossier config user.name $Prenom
git -C $Dossier config user.email "$($moi.id)+$($moi.login)@users.noreply.github.com"

# Mises à jour automatiques des compétences de l'équipe (réglage utilisateur de Claude Code).
$p = Join-Path $HOME '.claude\settings.json'
$d = if (Test-Path $p) { Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json } else { [pscustomobject]@{} }
if (-not $d.extraKnownMarketplaces) { $d | Add-Member -Force extraKnownMarketplaces ([pscustomobject]@{}) }
$d.extraKnownMarketplaces | Add-Member -Force lvorga ([pscustomobject]@{ source = [pscustomobject]@{ source = 'github'; repo = 'LVorga/marketplace' }; autoUpdate = $true })
if (-not $d.env) { $d | Add-Member -Force env ([pscustomobject]@{}) }
$d.env | Add-Member -Force CLAUDE_CODE_PLUGIN_PREFER_HTTPS '1'
New-Item -ItemType Directory -Force (Split-Path $p) | Out-Null
[IO.File]::WriteAllText($p, ($d | ConvertTo-Json -Depth 10))   # UTF-8 sans BOM

Write-Host "`nC'est prêt." -ForegroundColor Green
Write-Host "Pour travailler : ouvre PowerShell, tape  cd ~\wiki ; claude"
Write-Host "La première fois, réponds « oui » quand Claude demande de faire confiance au dossier."
