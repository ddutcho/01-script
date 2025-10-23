#!/bin/bash

echo "[*] Richiesta password sudo (una sola volta)..."
sudo -v || exit 1

echo "[*] Fermo i servizi..."
sudo systemctl stop newt.service
sudo systemctl disable newt.service
sudo systemctl stop check-newt.timer
sudo systemctl disable check-newt.timer
sudo systemctl disable check-newt.service

echo "[*] Rimuovo file di sistema..."
sudo rm -f /usr/local/bin/newt
sudo rm -f /usr/local/bin/newt-runner.sh
sudo rm -f /usr/local/bin/check-newt.sh
sudo rm -f /etc/newt.env

echo "[*] Rimuovo unità systemd..."
sudo rm -f /etc/systemd/system/newt.service
sudo rm -f /etc/systemd/system/check-newt.service
sudo rm -f /etc/systemd/system/check-newt.timer

echo "[*] Ricarico configurazione systemd..."
sudo systemctl daemon-reload
sudo systemctl reset-failed

echo "Tutti i componenti di Newt sono stati rimossi."
