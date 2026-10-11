#!/usr/bin/env bash
set -u
source "$(dirname "$0")/../installer.sh" --source-only
ko=0
t() { r=$(slug "$1"); if [ "$r" = "$2" ]; then echo "ok  - slug '$1'"; else echo "KO  - slug '$1' → '$r' (attendu '$2')"; ko=1; fi; }
t "lorenzo" "lorenzo"
t "Élodie" "elodie"
t "jean marc" "jean-marc"
t "Anne-Sophie" "anne-sophie"
t "  Zoë  " "zoe"
t "Hélène" "helene"
t "José" "jose"
t "Marie-Ève" "marie-eve"
t "Bjørn" "bjorn"
t "Œdipe" "oedipe"
t "N'Golo" "n-golo"
t "Françoise" "francoise"
exit $ko
