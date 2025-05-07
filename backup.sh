#!/bin/bash

# Définir la destination Backblaze et les identifiants Restic

export AWS_ACCESS_KEY_ID="<key ID>"
export AWS_SECRET_ACCESS_KEY="<Secret access key>"
export RESTIC_REPO="s3:<bucket location>"
export RESTIC_PASSWORD_FILE=<restic passwd>
STATUS_FILE="/var/log/backup.log"
LOCK_FILE="/var/run/backup_running.lock"
BACKUP_STATE_FILE="/var/log/backup_state.log"

# Supprimer l'ancien fichier de statut au début de la nouvelle sauvegarde
echo "Aucune sauvegarde en cours." > "$BACKUP_STATE_FILE"

# Fonction pour enregistrer les logs de statut et envoyer la progression avec wall
echo_status() {
    echo "$(date +'%Y-%m-%d %H:%M:%S') - $1" | tee -a "$STATUS_FILE"
}

echo_state() {
    echo "$1" > "$BACKUP_STATE_FILE"
    wall "$1"
}

# Vérifier si une autre instance tourne déjà
if [ -f "$LOCK_FILE" ]; then
    echo_status "Une sauvegarde est déjà en cours. Arrêt du script."
    exit 1
fi

# Créer le fichier de verrouillage
touch "$LOCK_FILE"

# Démarrer la sauvegarde
echo_status "Début de la sauvegarde Restic."
echo_state "Sauvegarde en cours..."
systemctl mask shutdown.target
shutdown -c  # Annule tout arrêt programmé

# Vérifier si le dépôt Restic est initialisé
if ! restic -r "$RESTIC_REPO" snapshots >/dev/null 2>&1; then
    echo_status "Initialisation du dépôt Restic..."
    restic -r "$RESTIC_REPO" init | while read -r line; do echo "$(date +'%Y-%m-%d %H:%M:%S') - $line" | tee -a "$STATUS_FILE"; done
    restic -r "$RESTIC_REPO" unlock
fi

for DIR in "/home" "/etc" "/data" "/opt" "/root" "/var/lib" "/var/ossec" "/var/www"; do
    if [ -d "$DIR" ]; then
        echo_status "Sauvegarde en cours: $DIR"
        echo_state "Sauvegarde en cours: $DIR"
        if [ "$DIR" = "/var/www" ]; then
            restic -r "$RESTIC_REPO" backup "$DIR" \
                --exclude="/var/www/Nekocorp-User-data/jellyfin-stack/radarr" \
                --exclude="/var/www/Nekocorp-User-data/jellyfin-stack/sonarr" \
                --exclude="/var/www/Nekocorp-User-data/jellyfin-stack/qbittorrent/downloads" \
                --exclude="/var/www/Nekocorp-User-data/jellyfin-stack/jellyfin/cache" \
                --verbose 2>&1 | while read -r line; do
                    echo "$(date +'%Y-%m-%d %H:%M:%S') - $line" | tee -a "$STATUS_FILE"
                done
        else
            restic -r "$RESTIC_REPO" backup "$DIR" --verbose 2>&1 | while read -r line; do
                echo "$(date +'%Y-%m-%d %H:%M:%S') - $line" | tee -a "$STATUS_FILE"
            done
        fi
        if [ $? -eq 0 ]; then
            echo_status "Sauvegarde de $DIR terminée avec succès."
        else
            echo_status "Erreur lors de la sauvegarde de $DIR."
        fi
    else
        echo_status "Le répertoire $DIR n'existe pas, saut de cette sauvegarde."
    fi
done


echo_status "Suppression des anciennes sauvegardes..."
restic -r "$RESTIC_REPO" forget --keep-within 3d --prune 2>&1 | while read -r line; do echo "$(date +'%Y-%m-%d %H:%M:%S') - $line" | tee -a "$STATUS_FILE"; done
if [ $? -eq 0 ]; then
    echo_status "Nettoyage terminé avec succès."
else
    echo_status "Erreur lors du nettoyage des anciennes sauvegardes."
fi

# Fin de la sauvegarde
CURRENT_DATE=$(date +'%Y-%m-%d')
CURRENT_TIME=$(date +'%H:%M:%S')
echo_status "Backup of $CURRENT_DATE successfully ended at $CURRENT_TIME."
echo_state "Backup of $CURRENT_DATE successfully ended at $CURRENT_TIME."

# Supprimer le fichier de verrouillage
rm -f "$LOCK_FILE"

echo_status "Réactivation de la possibilité d'arrêt du serveur."
systemctl unmask shutdown.target

# Vérifier si l'arrêt du serveur est prévu et déclencher l'arrêt si nécessaire
SHUTDOWN_TIME="00:30"
CURRENT_TIME=$(date +"%H:%M")
if [[ "$CURRENT_TIME" > "$SHUTDOWN_TIME" && "$SHUTDOWN_TIME" != "00:30" ]]; then
    echo_status "L'heure d'arrêt du serveur est atteinte. Extinction en cours..."
    shutdown -h now
else
    echo_status "Le serveur reste allumé."
fi
