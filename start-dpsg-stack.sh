#!/usr/bin/env bash
#
# NaMi 3.0 – lokalen Hitobito-Stack starten
# =========================================
#
# Richtet Hitobito Core + Pfadi-DE-Wagon + DPSG-Wagon lokal in Docker ein, startet
# die Umgebung und befüllt sie auf Wunsch mit Testdaten.
#
#   ./start-dpsg-stack.sh --seed
#
# Die ausführliche Anleitung steht in der README dieses Repositories:
# https://github.com/mvpfad/dpsg-stack

set -euo pipefail

# --------------------------------------------------------------------------
# Grundeinstellungen
# --------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Die mitgelieferte Compose-Datei reicht DISPLAY an den Container weiter. Ohne diese
# Zeile warnt Docker bei jedem Aufruf, dass die Variable nicht gesetzt sei.
export DISPLAY="${DISPLAY:-}"

# Wo die Hitobito-Quellen liegen. Überschreibbar, falls du sie schon woanders
# geklont hast: DPSG_STACK_DIR=/pfad/zu/hitobito_testing ./start-dpsg-stack.sh
STACK_DIR="${DPSG_STACK_DIR:-$SCRIPT_DIR/hitobito_testing}"
DEV_DIR="$STACK_DIR/development"
SEED_FILE="$SCRIPT_DIR/seeds/nami3_seed.rb"

APP_URL="http://localhost:3000"
MAIL_URL="http://localhost:1080"

# Wie lange auf die Anwendung gewartet wird (Sekunden). Der allererste Start
# baut Gems und Assets und braucht deshalb lange.
WAIT_TIMEOUT="${DPSG_STACK_TIMEOUT:-2700}"

# Eigener Name für die Containergruppe. Ohne ihn würde Docker den Verzeichnisnamen
# nehmen – der heißt immer "development". Zwei Installationen an verschiedenen Orten
# würden sich dann Container und Datenbank teilen und sich gegenseitig zerstören.
export COMPOSE_PROJECT_NAME="${DPSG_STACK_PROJECT:-nami3-dpsg}"

DEVELOPMENT_REPO="https://github.com/hitobito/development.git"
COMPOSITION_REPO="https://github.com/hitobito/ose_composition_dpsg.git"

# Core und Wagons liegen direkt in development/ – so erwartet es die Hitobito-
# Entwicklungsumgebung (siehe deren bin/all_repos).
SOURCE_REPOS=(hitobito hitobito_pfadi_de hitobito_dpsg)

# Liegt neben den Quellen und wird von der Entwicklungsumgebung ignoriert.
COMPOSITION_DIR="ose_composition_dpsg"

# Vom Seed erzeugte Übersichten, damit sie auch ohne erneutes Seeding angezeigt
# werden können.
USERS_CACHE="$STACK_DIR/.nami3-seed-users"
TREE_CACHE="$STACK_DIR/.nami3-seed-tree"

# --------------------------------------------------------------------------
# Ausgabe
# --------------------------------------------------------------------------

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'; C_BLUE=$'\033[34m'
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_BLUE=""
fi

STEP_NO=0
STEP_TOTAL=5

step() {
  STEP_NO=$((STEP_NO + 1))
  printf '%s[%d/%d]%s %s\n' "$C_BLUE$C_BOLD" "$STEP_NO" "$STEP_TOTAL" "$C_RESET" "$1"
}

info() { printf '      %s\n' "$1"; }
ok()   { printf '      %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$1"; }
warn() { printf '      %s!%s %s\n' "$C_YELLOW" "$C_RESET" "$1"; }

fail() {
  printf '\n%sFehler:%s %s\n' "$C_RED$C_BOLD" "$C_RESET" "$1" >&2
  shift || true
  for line in "$@"; do printf '  %s\n' "$line" >&2; done
  exit 1
}

# Füllt einen Text rechts mit Leerzeichen auf. printf '%-20s' würde bei Umlauten
# Bytes statt Zeichen zählen und die Tabelle verschieben.
pad() {
  local text="$1" width="$2" len=${#1}
  printf '%s' "$text"
  if [ "$len" -lt "$width" ]; then printf '%*s' "$((width - len))" ''; fi
}

# --------------------------------------------------------------------------
# Docker-Compose-Hülle
# --------------------------------------------------------------------------

compose() {
  ( cd "$DEV_DIR" && docker compose "$@" )
}

compose_quiet() {
  ( cd "$DEV_DIR" && docker compose "$@" >/dev/null 2>&1 )
}

stack_installed() {
  is_git_repo "$DEV_DIR/hitobito"
}

is_git_repo() {
  git -C "$1" rev-parse --git-dir >/dev/null 2>&1
}

rails_running() {
  [ -n "$(compose ps -q rails 2>/dev/null || true)" ]
}

app_reachable() {
  curl -fsS -o /dev/null --max-time 5 "$APP_URL/healthz" 2>/dev/null
}

# --------------------------------------------------------------------------
# Voraussetzungen
# --------------------------------------------------------------------------

check_prerequisites() {
  step "Voraussetzungen prüfen"

  command -v git >/dev/null 2>&1 || fail "Git ist nicht installiert." \
    "Installiere Git: https://git-scm.com/downloads"

  command -v docker >/dev/null 2>&1 || fail "Docker ist nicht installiert." \
    "Installiere Docker Desktop: https://www.docker.com/products/docker-desktop/"

  docker info >/dev/null 2>&1 || fail "Docker läuft nicht." \
    "Starte Docker Desktop und warte, bis das Wal-Symbol ruhig ist. Dann erneut versuchen."

  docker compose version >/dev/null 2>&1 || fail "'docker compose' steht nicht zur Verfügung." \
    "Du brauchst Docker Compose v2 (in Docker Desktop enthalten)."

  command -v curl >/dev/null 2>&1 || fail "curl ist nicht installiert."

  check_ports
  check_disk_space

  ok "Alles da."
}

check_ports() {
  local port busy=""
  for port in $(required_ports); do
    if port_in_use "$port" && ! stack_owns_port "$port"; then
      busy="$busy $port"
    fi
  done

  if [ -n "$busy" ]; then
    fail "Diese Ports sind schon belegt:$busy" \
      "Gebraucht werden unter anderem 3000 (Anwendung), 1080 (E-Mail-Postfach)," \
      "5432 (Datenbank) und 6379 (Zwischenspeicher)." \
      "Beende das Programm, das den Port benutzt – unter macOS/Linux findest du es mit:" \
      "  lsof -i :3000" \
      "Läuft vielleicht ein zweiter Hitobito-Stack? Dann hilft dort ein 'docker compose down'."
  fi
}

# Die benötigten Ports stehen in der Compose-Datei. Sie dort abzulesen statt sie fest
# einzutragen hält das Script gültig, wenn Hitobito seine Dienste umbaut.
required_ports() {
  local ports=""
  if [ -f "$DEV_DIR/docker-compose.yml" ]; then
    ports="$(grep -oE '"[0-9]+:[0-9]+"' "$DEV_DIR/docker-compose.yml" |
      tr -d '"' | cut -d: -f1 | sort -un | tr '\n' ' ')"
  fi
  printf '%s' "${ports:-3000 1080 5432 6379}"
}

port_in_use() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
  else
    # Ohne lsof lieber nichts behaupten.
    return 1
  fi
}

# Belegt unser eigener Stack den Port? Dann ist alles in Ordnung – "docker compose up"
# ordnet die laufenden Container selbst neu. Geprüft wird das gesamte Projekt und nicht
# nur die Anwendung, denn nach einem abgebrochenen Start laufen oft nur einzelne Dienste.
stack_owns_port() {
  stack_installed || return 1
  [ -n "$(compose ps -q 2>/dev/null || true)" ]
}

check_disk_space() {
  local avail_kb
  avail_kb="$(df -Pk "$SCRIPT_DIR" 2>/dev/null | awk 'NR==2 {print $4}')" || return 0
  [ -n "$avail_kb" ] || return 0
  # Gemessen belegt der Stack rund 8 GB (Images, Quellen, Volumes). Gewarnt wird
  # erst darunter, damit die Meldung nicht grundlos kommt.
  if [ "$avail_kb" -lt 10000000 ]; then
    warn "Weniger als 10 GB frei – der Stack belegt mit Images und Quellen etwa 8 GB."
  fi
}

# --------------------------------------------------------------------------
# Erstinstallation
# --------------------------------------------------------------------------

ensure_installed() {
  if stack_installed; then
    step "Hitobito-Quellen sind vorhanden"
    info "$DEV_DIR"
    return
  fi

  step "Hitobito herunterladen und einrichten (dauert einige Minuten)"
  install_stack
}

install_stack() {
  mkdir -p "$STACK_DIR"

  if [ ! -d "$DEV_DIR/.git" ]; then
    info "Lade die Docker-Entwicklungsumgebung …"
    rm -rf "$DEV_DIR"
    git clone --quiet "$DEVELOPMENT_REPO" "$DEV_DIR" ||
      fail "Konnte $DEVELOPMENT_REPO nicht laden." "Besteht eine Internetverbindung?"
  fi

  remove_old_layout
  fetch_composition
  checkout_sources

  open_ports_in_compose

  docker volume create hitobito_bundle >/dev/null
  docker volume create hitobito_yarn_cache >/dev/null

  info "Lade die Docker-Images (einige hundert Megabyte) …"
  pull_images || warn "Konnte nicht alle Images laden – es wird mit dem Vorhandenen versucht."

  ok "Quellen eingerichtet."
}

# Frühere Fassungen dieser Umgebung legten Core und Wagons unter development/app ab.
# Die Container migrieren das beim Start selbst, bleiben dabei aber an .git hängen.
# Deshalb wird der Rest dieser alten Ablage hier entfernt.
remove_old_layout() {
  [ -e "$DEV_DIR/app" ] || return 0

  # Eigene, noch nicht gesicherte Arbeit darf dabei nicht verloren gehen.
  local repo
  for repo in "$DEV_DIR/app" "$DEV_DIR/app"/hitobito*; do
    is_git_repo "$repo" || continue
    [ -z "$(git -C "$repo" status --porcelain --untracked-files=no \
      --ignore-submodules=all 2>/dev/null)" ] && continue
    fail "In $repo liegen ungespeicherte Änderungen." \
      "Hitobito hat die Verzeichnisstruktur geändert – der Ordner development/app wird" \
      "nicht mehr verwendet und muss weichen." \
      "Sichere deine Änderungen, danach räumt dieses Programm von allein auf:" \
      "  git -C $repo status"
  done

  info "Entferne die frühere Verzeichnisstruktur (development/app) …"
  chmod -R u+w "$DEV_DIR/app" 2>/dev/null || true
  rm -rf "$DEV_DIR/app"
}

# Das Zusammenstellungs-Repo hält fest, welche Versionen von Core und Wagons
# zusammen getestet wurden.
fetch_composition() {
  local dir="$DEV_DIR/$COMPOSITION_DIR"
  if is_git_repo "$dir"; then
    git -C "$dir" fetch --quiet origin || warn "Konnte die Versionsliste nicht auffrischen."
    git -C "$dir" reset --hard --quiet FETCH_HEAD 2>/dev/null || true
    return 0
  fi
  info "Lade die Versionsliste (Zusammenstellung für die DPSG) …"
  rm -rf "$dir"
  git clone --quiet "$COMPOSITION_REPO" "$dir" ||
    fail "Konnte $COMPOSITION_REPO nicht laden."
}

# Holt Core und Wagons als eigenständige Repositories direkt nach development/
# und stellt sie auf die in der Zusammenstellung festgehaltenen Stände.
checkout_sources() {
  local repo url commit target
  for repo in "${SOURCE_REPOS[@]}"; do
    url="$(composition_url "$repo")"
    commit="$(composition_commit "$repo")"
    target="$DEV_DIR/$repo"

    if ! is_git_repo "$target"; then
      info "Lade $(pretty_repo_name "$repo") …"
      rm -rf "$target"
      git clone --quiet "$url" "$target" || fail "Konnte $url nicht laden."
    fi

    [ -n "$commit" ] || continue
    if [ "$(git -C "$target" rev-parse HEAD 2>/dev/null)" = "$commit" ]; then
      continue
    fi
    git -C "$target" fetch --quiet origin || true
    git -C "$target" checkout --quiet --detach "$commit" ||
      fail "Konnte $(pretty_repo_name "$repo") nicht auf den passenden Stand bringen."
  done
}

composition_url() {
  git -C "$DEV_DIR/$COMPOSITION_DIR" config --file .gitmodules \
    --get "submodule.$1.url" 2>/dev/null || printf 'https://github.com/hitobito/%s.git' "$1"
}

composition_commit() {
  git -C "$DEV_DIR/$COMPOSITION_DIR" ls-tree HEAD "$1" 2>/dev/null | awk '{print $3}'
}

pretty_repo_name() {
  case "$1" in
    hitobito) printf 'Hitobito Core' ;;
    hitobito_pfadi_de) printf 'Pfadi-DE-Wagon' ;;
    hitobito_dpsg) printf 'DPSG-Wagon' ;;
    *) printf '%s' "$1" ;;
  esac
}

# Die mitgelieferte Compose-Datei bindet die Ports nur an 127.0.0.1. Das entfernen
# wir, damit die Dienste auch aus anderen Containern (z. B. Playwright) erreichbar sind.
open_ports_in_compose() {
  if grep -q '127\.0\.0\.1:' "$DEV_DIR/docker-compose.yml"; then
    if sed --version >/dev/null 2>&1; then
      sed -i 's/127\.0\.0\.1://g' "$DEV_DIR/docker-compose.yml"
    else
      sed -i '' 's/127\.0\.0\.1://g' "$DEV_DIR/docker-compose.yml"
    fi
  fi
}

# Hitobito würde beim ersten Start seine eigenen Beispieldaten anlegen – hunderte
# erfundene Personen in einer fremden Verbandsstruktur. Wir wollen stattdessen
# ausschließlich unsere eigenen Testdaten, deshalb SKIP_SEEDS.
write_compose_override() {
  local target="$DEV_DIR/docker-compose.override.yml"
  cat > "$target" <<'YAML'
# Diese Datei wird von start-dpsg-stack.sh erzeugt und bei jedem Start überschrieben.
#
# SKIP_SEEDS verhindert die mitgelieferten Beispieldaten von Hitobito. Die Testdaten
# für NaMi 3.0 kommen stattdessen aus seeds/nami3_seed.rb.
services:
  rails:
    environment:
      SKIP_SEEDS: "1"
YAML
}

# --------------------------------------------------------------------------
# Starten und warten
# --------------------------------------------------------------------------

# Holt die Images aus der Registry. Schlägt das fehl (etwa ohne Internet), baut es
# sie notfalls selbst – das dauert deutlich länger, kommt aber ohne Registry aus.
pull_images() {
  compose pull --quiet >/dev/null 2>&1 && return 0
  compose build --quiet >/dev/null 2>&1
}

start_containers() {
  step "Container starten"
  write_compose_override

  local log
  log="$(mktemp)"
  if ! compose up -d > "$log" 2>&1; then
    # Hitobito ändert gelegentlich die Startprogramme in seinen Images. Ein hier schon
    # vorhandenes, älteres Image kennt sie dann nicht – einmal nachladen und neu versuchen.
    if grep -qiE 'executable file not found|no such file or directory.*entrypoint' "$log"; then
      info "Die vorhandenen Docker-Images sind veraltet – lade die aktuellen …"
      pull_images || true
      if compose up -d > "$log" 2>&1; then
        rm -f "$log"
        ok "Container laufen."
        return
      fi
    fi

    # Startet die Datenbank nicht, bricht Docker alle davon abhängigen Dienste ab.
    # Die eigentliche Ursache steht dann nur in deren Protokoll.
    if grep -qiE 'postgres.*unhealthy|dependency failed to start' "$log"; then
      rm -f "$log"
      diagnose_postgres
    fi
    printf '%s\n' "$C_DIM"; cat "$log"; printf '%s\n' "$C_RESET"
    rm -f "$log"
    fail "Die Container konnten nicht gestartet werden." \
      "Die Ausgabe oben zeigt die Ursache, mehr steht in './start-dpsg-stack.sh --logs'."
  fi
  rm -f "$log"
  ok "Container laufen."
}

# wait_for_rails [soft]
# Mit "soft" wird im Fehlerfall nur ein Rückgabewert geliefert statt abzubrechen –
# das Update braucht die Gelegenheit, noch einen Hinweis auf die Sicherung zu geben.
wait_for_rails() {
  local soft="${1:-}"
  step "Auf die Anwendung warten"

  if app_reachable; then
    ok "Anwendung ist bereits erreichbar."
    return 0
  fi

  info "Beim allerersten Start werden Programmbibliotheken und Oberfläche gebaut."
  info "Das dauert je nach Rechner 15 bis 30 Minuten – du kannst in der Zeit etwas anderes machen."

  local start_time elapsed deadline
  start_time="$(date +%s)"
  deadline=$((start_time + WAIT_TIMEOUT))

  while :; do
    if app_reachable; then
      clear_progress_line
      elapsed=$(( $(date +%s) - start_time ))
      ok "Anwendung ist erreichbar (nach $((elapsed / 60)) Minuten $((elapsed % 60)) Sekunden)."
      return 0
    fi

    if [ "$(date +%s)" -ge "$deadline" ]; then
      clear_progress_line
      [ "$soft" = "soft" ] && return 1
      fail "Die Anwendung ist nach $((WAIT_TIMEOUT / 60)) Minuten immer noch nicht erreichbar." \
        "Sieh dir an, woran es hängt:" \
        "  ./start-dpsg-stack.sh --logs" \
        "Mit mehr Geduld: DPSG_STACK_TIMEOUT=5400 ./start-dpsg-stack.sh --seed"
    fi

    if ! rails_running; then
      clear_progress_line
      [ "$soft" = "soft" ] && return 1
      fail "Der Rails-Container läuft nicht mehr." \
        "Die Protokolle zeigen die Ursache:" \
        "  ./start-dpsg-stack.sh --logs"
    fi

    elapsed=$(( $(date +%s) - start_time ))
    printf '\r      %s… läuft seit %d:%02d Minuten%s' \
      "$C_DIM" "$((elapsed / 60))" "$((elapsed % 60))" "$C_RESET"
    sleep 10
  done
}

clear_progress_line() {
  printf '\r%*s\r' 60 ''
}

# --------------------------------------------------------------------------
# Testdaten
# --------------------------------------------------------------------------

run_seed() {
  step "Testdaten anlegen"

  [ -f "$SEED_FILE" ] || fail "Die Seed-Datei fehlt: $SEED_FILE"

  seed_hitobito_basics
  copy_seed_into_container

  local seed_log
  seed_log="$(mktemp)"
  if ! compose exec -T rails bin/rails runner /tmp/nami3_seed.rb > "$seed_log" 2>&1; then
    printf '%s\n' "$C_DIM"; tail -n 30 "$seed_log"; printf '%s\n' "$C_RESET"
    rm -f "$seed_log"
    fail "Die Testdaten konnten nicht angelegt werden." \
      "Häufigste Ursache: die Datenbank ist in einem halben Zustand." \
      "Mit './start-dpsg-stack.sh --reset' wird sie neu aufgebaut."
  fi

  grep '^SEED_USER|' "$seed_log" > "$USERS_CACHE" || true
  grep '^SEED_TREE|' "$seed_log" > "$TREE_CACHE" || true

  local summary
  summary="$(grep '^SEED_DONE|' "$seed_log" | head -n1 | cut -d'|' -f2- || true)"
  rm -f "$seed_log"

  ok "${summary:-Testdaten angelegt.}"
}

# Hitobito braucht ein paar Grunddaten, damit die Oberfläche funktioniert:
# Kontaktarten, Textbausteine für E-Mails und die Wurzelgruppe. NO_ENV sorgt dafür,
# dass dabei nicht die umfangreichen Beispieldaten aus db/seeds/development landen.
seed_hitobito_basics() {
  info "Grunddaten von Hitobito sicherstellen …"
  compose exec -T -e NO_ENV=1 rails bin/rails db:seed wagon:seed >/dev/null 2>&1 ||
    warn "Die Grunddaten konnten nicht geladen werden – der Seed versucht es trotzdem."
}

copy_seed_into_container() {
  if compose cp "$SEED_FILE" rails:/tmp/nami3_seed.rb >/dev/null 2>&1; then
    return
  fi
  # Ältere Compose-Versionen kennen 'cp' noch nicht.
  local container
  container="$(compose ps -q rails)"
  [ -n "$container" ] || fail "Der Rails-Container läuft nicht."
  docker cp "$SEED_FILE" "$container:/tmp/nami3_seed.rb" >/dev/null ||
    fail "Die Seed-Datei konnte nicht in den Container kopiert werden."
}

# --------------------------------------------------------------------------
# Einmalpasswörter für die Zwei-Faktor-Anmeldung
# --------------------------------------------------------------------------

TOTP_SECRET_DEFAULT="JBSWY3DPEHPK3PXPJBSWY3DPEHPK3PXP"

base32_to_hex() {
  local input="$1" alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
  local bits="" i j char prefix idx byte
  input="$(printf '%s' "$input" | tr -d '=' | tr '[:lower:]' '[:upper:]')"

  for (( i = 0; i < ${#input}; i++ )); do
    char="${input:i:1}"
    prefix="${alphabet%%"$char"*}"
    idx=${#prefix}
    [ "$idx" -lt 32 ] || return 1
    for (( j = 4; j >= 0; j-- )); do
      bits="$bits$(( (idx >> j) & 1 ))"
    done
  done

  while [ "${#bits}" -ge 8 ]; do
    byte="${bits:0:8}"
    bits="${bits:8}"
    printf '%02x' "$((2#$byte))"
  done
}

# Erzeugt den aktuell gültigen 6-stelligen Code nach RFC 6238 (SHA1, 30 Sekunden).
totp_now() {
  local secret="$1" hexkey counter message escaped digest offset part code
  command -v openssl >/dev/null 2>&1 || return 1

  hexkey="$(base32_to_hex "$secret")" || return 1
  counter=$(( $(date +%s) / 30 ))
  message="$(printf '%016x' "$counter")"
  escaped="$(printf '%s' "$message" | sed 's/../\\x&/g')"

  # shellcheck disable=SC2059  # Genau gewollt: printf soll die \xNN-Sequenzen auflösen.
  digest="$(printf "$escaped" |
    openssl dgst -sha1 -mac HMAC -macopt "hexkey:$hexkey" -binary 2>/dev/null |
    od -An -tx1 | tr -d ' \n')" || return 1
  [ "${#digest}" -eq 40 ] || return 1

  offset=$(( 16#${digest: -1} * 2 ))
  part="${digest:offset:8}"
  code=$(( (16#$part & 0x7fffffff) % 1000000 ))
  printf '%06d' "$code"
}

totp_seconds_left() {
  echo $(( 30 - ($(date +%s) % 30) ))
}

# --------------------------------------------------------------------------
# Abschlussübersicht
# --------------------------------------------------------------------------

print_summary() {
  local line

  printf '\n%s%s\n' "$C_GREEN$C_BOLD" "══════════════════════════════════════════════════════════════════════"
  printf '  NaMi 3.0 – DPSG-Stack läuft\n'
  printf '%s%s\n\n' "══════════════════════════════════════════════════════════════════════" "$C_RESET"

  printf '  %sMitgliederverwaltung%s  %s\n' "$C_BOLD" "$C_RESET" "$APP_URL"
  printf '  %sE-Mail-Postfach%s       %s\n' "$C_BOLD" "$C_RESET" "$MAIL_URL"

  print_tree
  print_users
  print_two_factor_hint

  printf '\n  %sWeiter geht es mit%s\n' "$C_BOLD" "$C_RESET"
  printf '    ./start-dpsg-stack.sh --status    Läuft alles?\n'
  printf '    ./start-dpsg-stack.sh --logs      Protokoll mitlesen\n'
  printf '    ./start-dpsg-stack.sh --stop      Alles anhalten\n'
  printf '    ./start-dpsg-stack.sh --reset     Testdaten neu aufbauen\n'
  printf '    ./start-dpsg-stack.sh --update    Hitobito aktualisieren, Daten behalten\n'
  printf '\n'
}

# Zeigt den Gruppenbaum. In gewachsenen Entwicklungsdatenbanken stehen oft noch
# Altbestände darin – deshalb nach einigen Zeilen abkürzen statt den Bildschirm zu fluten.
TREE_MAX_LINES=32

print_tree() {
  [ -s "$TREE_CACHE" ] || return 0

  local total shown=0 entry
  total="$(wc -l < "$TREE_CACHE" | tr -d ' ')"

  printf '\n  %sTestdaten – Gruppenstruktur%s\n' "$C_BOLD" "$C_RESET"
  while IFS='|' read -r _ entry; do
    shown=$((shown + 1))
    if [ "$shown" -gt "$TREE_MAX_LINES" ]; then
      printf '    %s… und %d weitere Gruppen (vollständig unter %s)%s\n' \
        "$C_DIM" "$((total - TREE_MAX_LINES))" "$APP_URL/groups/1" "$C_RESET"
      break
    fi
    printf '    %s\n' "$entry"
  done < "$TREE_CACHE"
}

print_users() {
  if [ ! -s "$USERS_CACHE" ]; then
    printf '\n  %sNoch keine Testdaten angelegt.%s Mit --seed nachholen.\n' "$C_YELLOW" "$C_RESET"
    return
  fi

  local password
  password="hito42bito"

  printf '\n  %sTestbenutzer%s – Passwort für alle: %s%s%s\n\n' \
    "$C_BOLD" "$C_RESET" "$C_BOLD" "$password" "$C_RESET"

  printf '    '; pad "E-Mail" 34; pad "Rolle" 32; pad "2FA" 5; printf 'Ebene\n'
  printf '    %s%s%s\n' "$C_DIM" "$(printf '%.0s─' $(seq 1 92))" "$C_RESET"

  # Die mit _ beginnenden Felder werden hier nicht angezeigt, müssen aber gelesen werden.
  local _marker _key email role group two_fa _purpose
  while IFS='|' read -r _marker _key email role group two_fa _purpose; do
    [ -n "$email" ] || continue
    printf '    '
    pad "$email" 34
    pad "$role" 32
    pad "$two_fa" 5
    printf '%s\n' "$group"
  done < "$USERS_CACHE"

  printf '\n    %sWozu welcher Benutzer gut ist, steht in der Dokumentation.%s\n' \
    "$C_DIM" "$C_RESET"
}

print_two_factor_hint() {
  [ -s "$USERS_CACHE" ] || return 0
  grep -q '|ja|' "$USERS_CACHE" || return 0

  printf '\n  %sAnmeldung mit zweitem Faktor%s\n' "$C_BOLD" "$C_RESET"
  printf '    Einige Rollen verlangen zusätzlich einen 6-stelligen Code.\n'

  local code seconds
  if code="$(totp_now "$TOTP_SECRET_DEFAULT")"; then
    seconds="$(totp_seconds_left)"
    printf '    Gerade gültig: %s%s %s%s  (noch %s Sekunden)\n' \
      "$C_BOLD$C_GREEN" "${code:0:3}" "${code:3:3}" "$C_RESET" "$seconds"
    printf '    Neuen Code holen: ./start-dpsg-stack.sh --code\n'
  else
    printf '    Code anzeigen: ./start-dpsg-stack.sh --code\n'
  fi

  printf '    Dauerhaft in einer Authenticator-App einrichten (einmal scannen oder eintippen):\n'
  printf '      otpauth://totp/NaMi3-Lokal?secret=%s&issuer=NaMi3\n' "$TOTP_SECRET_DEFAULT"
  printf '    %sTipp: Wer sich ohne App umsehen will, nimmt einen Benutzer mit 2FA = nein.%s\n' \
    "$C_DIM" "$C_RESET"
}

# --------------------------------------------------------------------------
# Befehle
# --------------------------------------------------------------------------

cmd_start() {
  local with_seed="$1"
  STEP_TOTAL=4
  [ "$with_seed" = "yes" ] && STEP_TOTAL=5

  check_prerequisites
  ensure_installed
  start_containers
  wait_for_rails
  if [ "$with_seed" = "yes" ]; then
    run_seed
  fi

  print_summary
}

cmd_reset() {
  require_installed

  printf '%sDie Datenbank wird gelöscht und mit frischen Testdaten neu aufgebaut.%s\n' \
    "$C_YELLOW" "$C_RESET"
  confirm "Weitermachen?" || exit 0

  STEP_TOTAL=4

  step "Datenbank verwerfen"
  # Die Datenablage der Datenbank einfach wegwerfen statt sie über Rails zu leeren:
  # Das geht auch dann, wenn die Datenbank gar nicht mehr startet – etwa weil Hitobito
  # auf eine andere PostgreSQL-Version umgestellt hat. Die beiden großen Zwischenspeicher
  # (hitobito_bundle, hitobito_yarn_cache) sind in der Compose-Datei als "external"
  # gekennzeichnet und bleiben dabei erhalten.
  compose down --volumes >/dev/null 2>&1 ||
    fail "Die Container ließen sich nicht abräumen."
  rm -f "$USERS_CACHE" "$TREE_CACHE"
  ok "Datenbank verworfen."

  start_containers

  wait_for_rails
  run_seed
  print_summary
}

# Sagt, warum die Datenbank nicht hochkommt. Der häufigste Fall nach einem Update ist
# ein Sprung der PostgreSQL-Hauptversion: die vorhandenen Dateien sind dann unlesbar.
diagnose_postgres() {
  local log
  log="$(compose logs --tail 40 --no-color postgres 2>/dev/null || true)"

  if printf '%s' "$log" | grep -q "database files are incompatible"; then
    local detail
    detail="$(printf '%s' "$log" | grep -m1 "The data directory was initialized" |
      sed 's/.*DETAIL:  //')"
    fail "Die vorhandenen Datenbankdateien passen nicht zur geforderten PostgreSQL-Version." \
      "${detail:-}" \
      "" \
      "Das passiert, wenn Hitobito auf eine andere PostgreSQL-Version umgestellt hat." \
      "Die alten Daten lassen sich nicht weiterverwenden – Testdaten baut man einfach neu auf:" \
      "" \
      "  ./start-dpsg-stack.sh --reset"
  fi

  if printf '%s' "$log" | grep -qi "out of memory\|no space left"; then
    fail "Der Datenbank gehen Speicher oder Plattenplatz aus." \
      "Gib Docker Desktop mehr Arbeitsspeicher oder schaffe Platz auf der Festplatte."
  fi

  fail "Die Datenbank ist nicht gestartet." \
    "Die letzten Meldungen:" \
    "$log"
}

cmd_update() {
  require_installed
  STEP_TOTAL=5

  step "Stand sichern"
  check_repos_clean
  local before_core before_pfadi before_dpsg
  before_core="$(repo_version hitobito)"
  before_pfadi="$(repo_version hitobito_pfadi_de)"
  before_dpsg="$(repo_version hitobito_dpsg)"
  local dump_file=""
  if rails_running; then
    dump_file="$(create_dump)" || true
  fi
  if [ -n "$dump_file" ]; then
    ok "Sicherung angelegt: $dump_file"
  else
    warn "Keine Sicherung möglich (läuft die Datenbank?) – es wird trotzdem aktualisiert."
  fi

  step "Neue Versionen holen"
  restore_managed_files
  git -C "$DEV_DIR" pull --quiet --ff-only ||
    fail "Die Entwicklungsumgebung konnte nicht aktualisiert werden."
  fetch_composition
  checkout_sources
  open_ports_in_compose
  ok "Quellen aktualisiert."

  step "Docker-Images aktualisieren"
  pull_images || warn "Konnte die Images nicht aktualisieren – es wird mit dem Vorhandenen versucht."
  ok "Images aktuell."

  step "Container neu starten"
  write_compose_override
  compose up -d >/dev/null 2>&1 || fail "Die Container konnten nicht gestartet werden." \
    "Mehr dazu steht in './start-dpsg-stack.sh --logs'."
  ok "Container laufen. Die Datenbank wird beim Start automatisch migriert."

  wait_for_rails_after_update "$dump_file"

  printf '\n  %sVersionen%s\n' "$C_BOLD" "$C_RESET"
  print_version_change "Hitobito Core" "$before_core" "$(repo_version hitobito)"
  print_version_change "Pfadi-DE-Wagon" "$before_pfadi" "$(repo_version hitobito_pfadi_de)"
  print_version_change "DPSG-Wagon" "$before_dpsg" "$(repo_version hitobito_dpsg)"

  printf '\n  Die Testdaten sind unverändert geblieben.\n'
  printf '  Frische Testdaten ergänzen: ./start-dpsg-stack.sh --seed\n'
  printf '  Komplett neu aufbauen:      ./start-dpsg-stack.sh --reset\n\n'
}

wait_for_rails_after_update() {
  local dump_file="$1"
  if wait_for_rails soft; then
    return 0
  fi
  fail "Die Anwendung startet nach dem Update nicht." \
    "Oft passt die neue Hitobito-Version nicht mehr zu den alten Testdaten." \
    "Frisch aufbauen:  ./start-dpsg-stack.sh --reset" \
    "${dump_file:+Deine Sicherung liegt unter $dump_file}"
}

# Dateien im development-Repo, die dieses Script selbst anpasst. Sie dürfen abweichen
# und werden vor dem Aktualisieren verworfen und danach neu geschrieben.
MANAGED_FILES=(docker-compose.yml)

# Bricht ab, wenn in den Quellen eigene Änderungen liegen, die ein Update zerstören würde.
# Die vom Script verwalteten Dateien und das Unterverzeichnis app/ (ein eigenes Repository)
# bleiben dabei außen vor.
check_repos_clean() {
  local dirty exclude=()
  local file
  for file in "${MANAGED_FILES[@]}"; do
    exclude+=(":(exclude)$file")
  done

  dirty="$(git -C "$DEV_DIR" status --porcelain --untracked-files=no -- \
    "${exclude[@]}" 2>/dev/null || true)"
  [ -z "$dirty" ] || warn_dirty "$DEV_DIR" "$dirty"

  # Core und Wagons – hier liegt echter Quellcode, der nicht verloren gehen darf.
  local repo
  for repo in "${SOURCE_REPOS[@]}"; do
    is_git_repo "$DEV_DIR/$repo" || continue
    dirty="$(git -C "$DEV_DIR/$repo" status --porcelain --untracked-files=no \
      --ignore-submodules=all 2>/dev/null || true)"
    [ -z "$dirty" ] || warn_dirty "$DEV_DIR/$repo" "$dirty"
  done
}

warn_dirty() {
  fail "In $1 gibt es ungespeicherte Änderungen." \
    "Das Update würde sie überschreiben. Sichere oder verwirf sie zuerst:" \
    "  git -C $1 status" \
    "" \
    "Betroffen:" \
    "$2"
}

# Setzt die vom Script angepassten Dateien zurück, damit git pull nicht an ihnen scheitert.
restore_managed_files() {
  local file
  for file in "${MANAGED_FILES[@]}"; do
    git -C "$DEV_DIR" checkout -- "$file" 2>/dev/null || true
  done
}

repo_version() {
  local path="$DEV_DIR/$1"
  # Bei Submodulen ist .git eine Datei, kein Verzeichnis – deshalb git selbst fragen.
  git -C "$path" rev-parse --git-dir >/dev/null 2>&1 || { printf 'unbekannt'; return; }
  git -C "$path" log -1 --format='%h (%ad)' --date=short 2>/dev/null || printf 'unbekannt'
}

print_version_change() {
  local name="$1" before="$2" after="$3"
  printf '    '
  pad "$name" 18
  if [ "$before" = "$after" ]; then
    printf '%s  (unverändert)\n' "$after"
  else
    printf '%s  →  %s%s%s\n' "$before" "$C_GREEN" "$after" "$C_RESET"
  fi
}

create_dump() {
  local dumps_dir="$STACK_DIR/dumps" target
  mkdir -p "$dumps_dir"
  target="$dumps_dir/$(date +%Y-%m-%d-%H%M%S).sql.gz"
  # shellcheck disable=SC2016  # Die Variablen sollen erst im Container aufgelöst werden.
  if compose exec -T postgres sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB"' 2>/dev/null |
      gzip > "$target"; then
    # Ein leerer Dump nützt niemandem.
    if [ -s "$target" ]; then printf '%s' "$target"; return 0; fi
  fi
  rm -f "$target"
  return 1
}

cmd_stop() {
  require_installed
  compose down
  printf '%sDer Stack ist angehalten.%s Weiter mit: ./start-dpsg-stack.sh --start\n' \
    "$C_GREEN" "$C_RESET"
}

cmd_status() {
  printf '%sQuellen%s\n' "$C_BOLD" "$C_RESET"
  if stack_installed; then
    printf '  Ort: %s\n' "$DEV_DIR"
    local repo
    for repo in "${SOURCE_REPOS[@]}"; do
      printf '  '; pad "$(pretty_repo_name "$repo")" 18
      printf '%s\n' "$(repo_version "$repo")"
    done
  else
    printf '  Noch nicht eingerichtet. Starte mit: ./start-dpsg-stack.sh --seed\n'
    return
  fi

  printf '\n%sContainer%s\n' "$C_BOLD" "$C_RESET"
  if ! docker info >/dev/null 2>&1; then
    printf '  Docker läuft nicht.\n'
    return
  fi
  compose ps 2>/dev/null | sed 's/^/  /'

  printf '\n%sErreichbarkeit%s\n' "$C_BOLD" "$C_RESET"
  if app_reachable; then
    printf '  %s✓%s Mitgliederverwaltung  %s\n' "$C_GREEN" "$C_RESET" "$APP_URL"
  else
    printf '  %s✗%s Mitgliederverwaltung  %s (noch) nicht erreichbar\n' "$C_RED" "$C_RESET" "$APP_URL"
  fi

  if [ -s "$USERS_CACHE" ]; then
    print_users
    print_two_factor_hint
  fi
  printf '\n'
}

cmd_logs() {
  require_installed
  compose logs -f --tail 100 rails
}

cmd_code() {
  local code seconds
  if code="$(totp_now "$TOTP_SECRET_DEFAULT")"; then
    seconds="$(totp_seconds_left)"
    printf '%s%s %s%s   (noch %s Sekunden gültig)\n' \
      "$C_BOLD" "${code:0:3}" "${code:3:3}" "$C_RESET" "$seconds"
  else
    fail "Der Code konnte nicht berechnet werden (openssl fehlt?)." \
      "Richte stattdessen eine Authenticator-App ein:" \
      "  otpauth://totp/NaMi3-Lokal?secret=$TOTP_SECRET_DEFAULT&issuer=NaMi3"
  fi
}

cmd_reinstall() {
  printf '%sAlle heruntergeladenen Quellen und die Datenbank werden gelöscht.%s\n' \
    "$C_YELLOW$C_BOLD" "$C_RESET"
  printf 'Betroffen: %s\n' "$STACK_DIR"
  printf 'Danach wird alles neu geladen – das dauert wieder 15 bis 30 Minuten.\n'
  confirm "Wirklich von vorn anfangen?" || exit 0

  assert_safe_to_delete "$STACK_DIR"

  if stack_installed; then
    compose down -v >/dev/null 2>&1 || true
  fi
  chmod -R u+w "$STACK_DIR" 2>/dev/null || true
  rm -rf "$STACK_DIR"
  printf '%sGelöscht.%s Der Stack wird jetzt neu aufgebaut.\n\n' "$C_GREEN" "$C_RESET"

  cmd_start yes
}

# Schutz vor einem falsch gesetzten DPSG_STACK_DIR: gelöscht wird nur, was auch
# wirklich wie ein heruntergeladener Hitobito-Stack aussieht.
assert_safe_to_delete() {
  local path="$1"
  case "$path" in
    "" | "/" | "$HOME" | "$HOME/")
      fail "Der Pfad '$path' wird aus Sicherheitsgründen nicht gelöscht."
      ;;
  esac
  [ -d "$path" ] || fail "Es gibt nichts zu löschen – '$path' existiert nicht."
  [ -d "$path/development" ] ||
    fail "In '$path' liegt keine Hitobito-Entwicklungsumgebung." \
      "Zur Sicherheit wird nichts gelöscht. Prüfe DPSG_STACK_DIR."
}

confirm() {
  local answer
  printf '%s [j/N] ' "$1"
  read -r answer || answer=""
  case "$answer" in
    [jJyY]*) return 0 ;;
    *) printf 'Abgebrochen.\n'; return 1 ;;
  esac
}

require_installed() {
  stack_installed || fail "Der Stack ist noch nicht eingerichtet." \
    "Hole das mit einem Befehl nach:" \
    "  ./start-dpsg-stack.sh --seed"
}

# --------------------------------------------------------------------------
# Hilfe
# --------------------------------------------------------------------------

usage() {
  cat <<HELP
${C_BOLD}NaMi 3.0 – lokaler Hitobito-Stack${C_RESET}

Richtet Hitobito Core, den Pfadi-DE-Wagon und den DPSG-Wagon lokal in Docker ein.

${C_BOLD}Der übliche Weg${C_RESET}
  ./start-dpsg-stack.sh --seed      Einrichten, starten und mit Testdaten füllen

${C_BOLD}Alle Befehle${C_RESET}
  --seed        Stack starten und Testdaten anlegen (beim ersten Mal inkl. Einrichtung)
  --start       Nur starten, vorhandene Daten bleiben unberührt
  --update      Hitobito auf neuere Versionen heben, Daten bleiben erhalten
  --reset       Datenbank leeren und Testdaten frisch anlegen
  --reinstall   Alles löschen und komplett neu herunterladen
  --stop        Container anhalten
  --status      Zeigt Versionen, Container und Testbenutzer
  --logs        Protokoll der Anwendung mitlesen (Abbruch mit Strg+C)
  --code        Aktuellen Code für die Zwei-Faktor-Anmeldung anzeigen
  --help        Diese Übersicht

${C_BOLD}Welcher Befehl wann?${C_RESET}
  --update      Neuer Programmstand, deine Testdaten bleiben
  --reset       Programmstand bleibt, Testdaten werden frisch aufgebaut
  --reinstall   Alles auf Anfang

${C_BOLD}Einstellungen über Umgebungsvariablen${C_RESET}
  DPSG_STACK_DIR       Ort der Hitobito-Quellen (Vorgabe: $STACK_DIR)
  DPSG_STACK_TIMEOUT   Wartezeit auf die Anwendung in Sekunden (Vorgabe: $WAIT_TIMEOUT)
  DPSG_STACK_PROJECT   Name der Containergruppe (Vorgabe: $COMPOSE_PROJECT_NAME)

${C_BOLD}Ausführliche Anleitung${C_RESET}
  https://github.com/mvpfad/dpsg-stack
HELP
}

# --------------------------------------------------------------------------
# Einstieg
# --------------------------------------------------------------------------

main() {
  case "${1:-}" in
    --seed)      cmd_start yes ;;
    --start)     cmd_start no ;;
    --update)    cmd_update ;;
    --reset)     cmd_reset ;;
    --reinstall) cmd_reinstall ;;
    --stop)      cmd_stop ;;
    --status)    cmd_status ;;
    --logs)      cmd_logs ;;
    --code)      cmd_code ;;
    --help|-h)   usage ;;
    "")          usage; printf '\n'; cmd_status ;;
    *)
      printf '%sUnbekannte Angabe: %s%s\n\n' "$C_RED" "$1" "$C_RESET" >&2
      usage >&2
      exit 1
      ;;
  esac
}

main "$@"
