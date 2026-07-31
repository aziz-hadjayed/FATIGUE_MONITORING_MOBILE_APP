#!/bin/bash
# /backend/app/infra/scripts/update.sh

PATH_APP="/media/mohamedaziz-hadjayed/D/aziz_data/fatigue_detection/App/"

LOG_FILE="/var/log/update-fastapi.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')
MAX_LINES=1000

# Rotation : garder seulement les 1000 dernières lignes
if [ -f "$LOG_FILE" ]; then
    LINE_COUNT=$(wc -l < "$LOG_FILE")
    if [ "$LINE_COUNT" -gt "$MAX_LINES" ]; then
        tail -n "$MAX_LINES" "$LOG_FILE" > /tmp/log-temp && mv /tmp/log-temp "$LOG_FILE"
    fi
fi

echo "[$DATE] === Mise à jour Fatigue Monitoring ===" >> $LOG_FILE

# 1. Python packages
echo "[$DATE] [1/3] Mise à jour Python..." >> $LOG_FILE
cd $PATH_APP
source .venv/bin/activate
cd backend/
pip install --upgrade -r requirements-pi4.txt >> $LOG_FILE 2>&1

# 2. Redémarrer FastAPI
echo "[$DATE] [2/3] Redémarrage FastAPI..." >> $LOG_FILE
systemctl restart fastapi >> $LOG_FILE 2>&1

# 3. Vérifier services
echo "[$DATE] [3/3] Vérification..." >> $LOG_FILE
systemctl status fastapi --no-pager >> $LOG_FILE 2>&1
systemctl status fail2ban --no-pager >> $LOG_FILE 2>&1

echo "[$DATE] === Terminé ===" >> $LOG_FILE