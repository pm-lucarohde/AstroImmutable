#!/bin/bash
# Checkt alle 2 Sekunden, ob der Trash-Ordner existiert (falls noch nie gelöscht wurde)
while [ ! -d "$HOME/.local/share/Trash/info" ]; do
    sleep 5
done

# Überwacht den Papierkorb
inotifywait -m -e delete -e create -e moved_to -e moved_from "$HOME/.local/share/Trash/info" |
while read -r path action file; do
    dbus-send --type=signal /org/kde/KDirNotify org.kde.KDirNotify.FilesChanged string:'trash:/'
done