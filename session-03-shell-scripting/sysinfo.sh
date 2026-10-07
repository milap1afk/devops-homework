#!/usr/bin/env bash
# System Information Script (Session 3 homework)
# Prints date, hostname, user, disk usage and processes, then saves the
# process list to a file inside a directory named by the user.

# ---- Variables -------------------------------------------------------
CURRENT_DATE=$(date)
HOST_NAME=$(hostname)
USER_NAME=$(whoami)

echo "========== System Information =========="
echo "Date     : $CURRENT_DATE"
echo "Hostname : $HOST_NAME"
echo "Username : $USER_NAME"
echo

echo "---------- Disk Usage (df -h) ----------"
df -h
echo

echo "---------- Running Processes (top 10) ----------"
ps aux | head -n 11
echo

# ---- User input ------------------------------------------------------
read -p "Enter a directory name to save the report: " DIR_NAME
DIR_NAME=${DIR_NAME:-sysinfo_report}       # default if user just presses Enter

mkdir -p "$DIR_NAME"                        # create the directory
REPORT_FILE="$DIR_NAME/processes.txt"
touch "$REPORT_FILE"                        # create the file

ps aux > "$REPORT_FILE"                     # > output redirection (overwrites)

echo "Saved $(wc -l < "$REPORT_FILE") lines of process info to $REPORT_FILE"
echo "Report created by $USER_NAME on $HOST_NAME at $CURRENT_DATE"
