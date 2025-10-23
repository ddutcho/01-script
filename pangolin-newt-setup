#!/usr/bin/env bash
set -euo pipefail

# setup-newt.sh — Installazione Newt + servizio systemd + healthcheck (robusto e idempotente)
# Testato su Ubuntu/Debian con systemd. Richiede privilegi root.

assert_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "Devi eseguire questo script come root (sudo)." >&2
    exit 1
  fi
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Comando richiesto non trovato: $1" >&2; exit 1; }
}

confirm() {
  local prompt="${1:-Confermi?} [s/N]: "
  read -r -p "$prompt" ans || true
  [[ "${ans,,}" == "s" || "${ans,,}" == "si" || "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}

install_newt_official() {
  echo "[INFO] Installazione Newt con installer ufficiale..."
  # Installer ufficiale (potrebbe mettere newt in ~/.local/bin se lanciato come utente non-root)
  curl -fsSL https://digpangolin.com/get-newt.sh | bash || true

  # Proviamo a localizzare il binario in tutti i casi (PATH o ~/.local/bin del SUDO_USER)
  if command -v newt >/dev/null 2>&1; then
    echo "[INFO] Trovato newt in $(command -v newt)"
    return 0
  fi

  local su_home=""
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    su_home="$(getent passwd "${SUDO_USER}" | cut -d: -f6 || true)"
    if [[ -n "$su_home" && -x "$su_home/.local/bin/newt" ]]; then
      echo "[INFO] Trovato newt in $su_home/.local/bin/newt"
      return 0
    fi
  fi

  echo "Errore: l'installer ufficiale non ha prodotto un binario raggiungibile." >&2
  exit 1
}

resolve_newt_src() {
  # Restituisce il path effettivo del binario newt
  if [[ -x "/usr/local/bin/newt" ]]; then
    echo "/usr/local/bin/newt"
    return 0
  fi
  if command -v newt >/dev/null 2>&1; then
    command -v newt
    return 0
  fi
  local su_home=""
  if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
    su_home="$(getent passwd "${SUDO_USER}" | cut -d: -f6 || true)"
    if [[ -n "$su_home" && -x "$su_home/.local/bin/newt" ]]; then
      echo "$su_home/.local/bin/newt"
      return 0
    fi
  fi
  echo "newt non trovato" >&2
  return 1
}

normalize_newt_to_usr_local_bin() {
  # Copia/sincronizza newt in /usr/local/bin/newt per l'uso con systemd
  local src
  src="$(resolve_newt_src)"
  if [[ "$src" != "/usr/local/bin/newt" ]]; then
    echo "[INFO] Normalizzo newt in /usr/local/bin/newt (sorgente: $src)"
    install -m 0755 "$src" /usr/local/bin/newt
  else
    echo "[INFO] newt è già in /usr/local/bin/newt"
  fi
  if ! /usr/local/bin/newt --version >/dev/null 2>&1; then
    echo "Errore: /usr/local/bin/newt non è eseguibile." >&2
    exit 1
  fi
}

prompt_inputs() {
  echo "== Parametri di connessione a Pangolin/Newt =="
  read -r -p "Endpoint (es. https://pangolin.tuodominio.tld): " PANGOLIN_ENDPOINT
  read -r -p "Newt ID: " NEWT_ID
  read -r -s -p "Newt Secret: " NEWT_SECRET; echo

  echo "== Opzioni avanzate =="
  if confirm "Abilitare --accept-clients (consente connessioni client al tuo Newt)?"; then
    ACCEPT_CLIENTS=true
  else
    ACCEPT_CLIENTS=false
  fi

  if confirm "Usare modalità --native (WireGuard kernel, richiede privilegi)?"; then
    USE_NATIVE=true
  else
    USE_NATIVE=false
  fi

  read -r -p "Percorso file di health (default: /run/newt/healthy): " HEALTH_FILE_INPUT || true
  HEALTH_FILE="${HEALTH_FILE_INPUT:-/run/newt/healthy}"

  # Validazioni
  if [[ -z "$PANGOLIN_ENDPOINT" || -z "$NEWT_ID" || -z "$NEWT_SECRET" ]]; then
    echo "Endpoint/ID/Secret non possono essere vuoti." >&2
    exit 1
  fi
  if [[ ! "$PANGOLIN_ENDPOINT" =~ ^https?:// ]]; then
    echo "Endpoint deve iniziare con http:// o https://." >&2
    exit 1
  fi
}

create_system_user() {
  if ! id -u newt >/dev/null 2>&1; then
    useradd -r -s /usr/sbin/nologin -d /var/lib/newt newt
  fi
  mkdir -p /var/lib/newt /etc/newt /var/log/newt
  chown -R newt:newt /var/lib/newt /var/log/newt
  chmod 0750 /var/lib/newt /var/log/newt
}

write_config() {
  # Conserviamo parametri in /etc/newt/config.json (più sicuro dei flag su process list)
  cat >/etc/newt/config.json <<JSON
{
  "id": "$(printf '%s' "$NEWT_ID")",
  "secret": "$(printf '%s' "$NEWT_SECRET")",
  "endpoint": "$(printf '%s' "$PANGOLIN_ENDPOINT")",
  "tlsClientCert": ""
}
JSON
  chmod 0600 /etc/newt/config.json
  chown root:root /etc/newt/config.json

  # Env file per opzioni runtime
  cat >/etc/newt/newt.env <<ENV
CONFIG_FILE=/etc/newt/config.json
HEALTH_FILE=${HEALTH_FILE}
LOG_LEVEL=INFO
ACCEPT_CLIENTS=${ACCEPT_CLIENTS}
USE_NATIVE_INTERFACE=${USE_NATIVE}
INTERFACE=newt
ENV
  chmod 0640 /etc/newt/newt.env
}

write_service_units() {
  local run_user="newt"
  local caps=""
  if [[ "${USE_NATIVE}" == "true" ]]; then
    # In native mode servono capability di rete
    run_user="root"
    caps="CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW"
  fi

  local NEWT_BIN="/usr/local/bin/newt"

  # Servizio principale
  cat >/etc/systemd/system/newt.service <<UNIT
[Unit]
Description=Newt (Pangolin) client
After=network-online.target
Wants=network-online.target systemd-networkd-wait-online.service

[Service]
User=${run_user}
Group=${run_user}
EnvironmentFile=/etc/newt/newt.env
RuntimeDirectory=newt
RuntimeDirectoryMode=0755
# Esegue il binario; parametri forniti da CONFIG_FILE per non esporre segreti su argv
ExecStart=${NEWT_BIN}
Restart=always
RestartSec=3
LimitNOFILE=65535
StandardOutput=journal
StandardError=journal
${caps}
KillSignal=SIGTERM
TimeoutStopSec=15

[Install]
WantedBy=multi-user.target
UNIT

  # Healthcheck: riavvia se manca/è stantio il file di salute
  cat >/usr/local/sbin/newt-healthcheck.sh <<'HCSH'
#!/usr/bin/env bash
set -euo pipefail
HEALTH_FILE="${HEALTH_FILE:-/run/newt/healthy}"
STALE_AFTER="${STALE_AFTER:-45}"

if [[ ! -e "$HEALTH_FILE" ]]; then
  systemctl restart newt.service
  exit 1
fi

now=$(date +%s)
mtime=$(stat -c %Y "$HEALTH_FILE")
age=$(( now - mtime ))
if (( age > STALE_AFTER )); then
  systemctl restart newt.service
  exit 2
fi
exit 0
HCSH
  chmod 0755 /usr/local/sbin/newt-healthcheck.sh

  # Service oneshot del healthcheck
  cat >/etc/systemd/system/newt-healthcheck.service <<HCS
[Unit]
Description=Healthcheck per Newt (riavvia se unhealthy)
After=newt.service

[Service]
Type=oneshot
EnvironmentFile=/etc/newt/newt.env
ExecStart=/usr/local/sbin/newt-healthcheck.sh
HCS

  # Timer ogni 30s
  cat >/etc/systemd/system/newt-healthcheck.timer <<HCT
[Unit]
Description=Esegui healthcheck Newt ogni 30 secondi

[Timer]
OnBootSec=30s
OnUnitActiveSec=30s
AccuracySec=5s
Unit=newt-healthcheck.service

[Install]
WantedBy=timers.target
HCT

  systemctl daemon-reload
  systemctl enable --now newt.service
  systemctl enable --now newt-healthcheck.timer
}

summary() {
  echo
  echo "== Installazione completata =="
  echo "Endpoint:        $PANGOLIN_ENDPOINT"
  echo "Accept clients:  $ACCEPT_CLIENTS"
  echo "Native mode:     $USE_NATIVE"
  echo "Health file:     $HEALTH_FILE"
  echo
  echo "Comandi utili:"
  echo "  systemctl status newt.service"
  echo "  journalctl -u newt.service -f"
  echo "  systemctl list-timers | grep newt-healthcheck"
  echo "  journalctl -u newt-healthcheck.service -f"
  echo
  echo "File creati:"
  echo "  /usr/local/bin/newt                    (binario normalizzato)"
  echo "  /etc/newt/config.json                  (parametri id/secret/endpoint)"
  echo "  /etc/newt/newt.env                     (opzioni runtime e HEALTH_FILE)"
  echo "  /usr/local/sbin/newt-healthcheck.sh"
  echo "  /etc/systemd/system/newt.service"
  echo "  /etc/systemd/system/newt-healthcheck.service"
  echo "  /etc/systemd/system/newt-healthcheck.timer"
}

main() {
  assert_root
  need_cmd curl
  need_cmd stat
  need_cmd systemctl
  need_cmd getent
  need_cmd install

  install_newt_official          # 1) installer ufficiale
  normalize_newt_to_usr_local_bin # 2) garantisce /usr/local/bin/newt
  prompt_inputs                  # 3) acquisizione parametri
  create_system_user             # 4) utente di sistema e directory
  write_config                   # 5) config sicura
  write_service_units            # 6) service + healthcheck timer
  summary
}

main "$@"
