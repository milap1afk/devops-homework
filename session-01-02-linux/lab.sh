#!/usr/bin/env bash
# Runs inside the linux-lab container (see README "How to reproduce"). Prints commands + output.
run() { echo "\$ $*"; eval "$@" 2>&1; echo; }
task="$1"
cd /root

if [ "$task" = links ]; then
  rm -rf /root/links-lab; mkdir /root/links-lab; cd /root/links-lab
  run 'echo "original content" > original.txt'
  run 'ln -s original.txt soft.txt        # soft (symbolic) link'
  run 'ln original.txt hard.txt           # hard link'
  echo "# -i shows inode numbers: hard.txt shares original.txt's inode, soft.txt has its own"
  run 'ls -li'
  run 'stat -c "%n  inode=%i  links=%h  type=%F" original.txt hard.txt soft.txt'
  run 'readlink soft.txt'
  run 'echo "edited via hard link" >> hard.txt; cat original.txt'
  echo "# Delete the original file"
  run 'rm original.txt'
  run 'ls -li'
  run 'cat hard.txt     # still works: data lives while link count > 0'
  run 'cat soft.txt     # broken: it pointed to a NAME that no longer exists'
  run 'find . -xtype l  # find dangling symlinks'
  echo "# Soft links can point to directories and across filesystems; hard links cannot"
  run 'ln -s /etc etc-link && ls -ld etc-link'
  run 'ln /etc etc-hard'
  run 'ln /proc/version proc-hard     # /proc is a different filesystem'
  echo "# Deleting links"
  run 'rm soft.txt etc-link     # or: unlink soft.txt'
  run 'rm hard.txt'
  run 'ls -la'
fi

if [ "$task" = users ]; then
  userdel -r alice >/dev/null 2>&1; userdel -r bob >/dev/null 2>&1
  run 'ls -l $(command -v adduser) $(command -v useradd)'
  run 'head -1 /usr/sbin/adduser    # adduser is a Perl script (front end)'
  run 'file /usr/sbin/useradd 2>/dev/null || echo "useradd: compiled binary (low-level tool)"'
  echo "# ---- useradd with NO options (low-level) ----"
  run 'useradd bob'
  run 'getent passwd bob'
  run 'ls -ld /home/bob'
  run 'grep "^bob:" /etc/shadow | cut -d: -f1,2'
  echo "# no home dir, shell = /bin/sh, password locked (!) -> needs extra flags"
  echo "# ---- adduser (recommended on Ubuntu/Debian) ----"
  run 'adduser --gecos "Alice Student" --disabled-password alice'
  run 'echo "alice:Devops@123" | chpasswd'
  run 'getent passwd alice'
  run 'ls -la /home/alice'
  run 'id alice'
  run 'usermod -aG sudo alice && id alice'
  run 'su - alice -c "whoami; pwd; echo \$SHELL"'
  echo "# useradd equivalent of adduser needs flags:"
  run 'echo "useradd -m -s /bin/bash -c \"Alice Student\" alice && passwd alice"'
  run 'userdel -r bob 2>&1 | grep -v "mail spool"; getent passwd bob || echo "bob removed"'
fi

if [ "$task" = journal ]; then
  cat > /usr/local/bin/hello-devops.sh <<'X'
#!/bin/bash
i=1
# "<4>" / "<3>" prefixes set the syslog priority (warning / err) that journald records
while true; do
  echo "hello-devops heartbeat #$i"
  [ $((i % 3)) -eq 0 ] && echo "<4>WARNING: slow response on beat $i"
  [ $((i % 5)) -eq 0 ] && echo "<3>ERROR: simulated failure on beat $i"
  i=$((i+1)); sleep 1
done
X
  chmod +x /usr/local/bin/hello-devops.sh
  cat > /etc/systemd/system/hello-devops.service <<'X'
[Unit]
Description=Hello DevOps demo service

[Service]
ExecStart=/usr/local/bin/hello-devops.sh
Restart=always

[Install]
WantedBy=multi-user.target
X
  systemctl daemon-reload
  run 'cat /etc/systemd/system/hello-devops.service'
  run 'systemctl enable --now hello-devops.service'
  sleep 7
  run 'systemctl status hello-devops --no-pager | head -8'
  echo "# ---- system logs ----"
  run 'journalctl --no-pager -n 10                 # last 10 lines of the whole system journal'
  run 'journalctl --list-boots --no-pager'
  run 'journalctl -b --no-pager | head -5          # logs from current boot'
  run 'journalctl -p err --no-pager -n 5           # only priority err and worse'
  run 'journalctl --since "5 minutes ago" --no-pager | tail -3'
  run 'journalctl --disk-usage'
  echo "# ---- logs for ONE service ----"
  run 'journalctl -u hello-devops --no-pager -n 8'
  run 'journalctl -u hello-devops -p warning --no-pager -n 4      # warning and worse'
  run 'journalctl -u hello-devops -p err --no-pager               # errors only'
  run 'journalctl -u hello-devops -o short-iso --no-pager -n 2'
  run 'journalctl -u hello-devops -o json-pretty --no-pager -n 1 | grep -E "MESSAGE\"|_PID|_SYSTEMD_UNIT|PRIORITY"'
  run 'journalctl -u cron --no-pager -n 3'
  run 'timeout 3 journalctl -u hello-devops -n 2 -f --no-pager    # -f follows live, like tail -f'
  run 'systemctl disable --now hello-devops.service'
fi

if [ "$task" = cheatsheet ]; then
  rm -rf /root/practice; mkdir -p /root/practice && cd /root/practice
  echo "# ---- Navigation & files ----"
  run 'pwd'
  run 'mkdir -p project/{src,logs,docs} && touch project/src/app.py project/docs/README.md'
  run 'tree project'
  run 'cp project/src/app.py project/src/app_backup.py && mv project/docs/README.md project/'
  run 'ls -lah project'
  run 'echo -e "error: disk full\ninfo: started\nerror: timeout\ninfo: ok" > project/logs/app.log'
  run 'cat project/logs/app.log'
  run 'head -2 project/logs/app.log; tail -1 project/logs/app.log'
  run 'wc -l project/logs/app.log'
  echo "# ---- Search & text processing ----"
  run 'grep -n "error" project/logs/app.log'
  run 'grep -c "info" project/logs/app.log'
  run 'find project -name "*.py"'
  run 'cut -d: -f1 project/logs/app.log | sort | uniq -c'
  run 'awk -F: '"'"'{print $2}'"'"' project/logs/app.log'
  run 'sed "s/error/ERROR/" project/logs/app.log'
  echo "# ---- Permissions & ownership ----"
  run 'chmod 750 project/src/app.py && ls -l project/src/app.py'
  run 'chmod u+x,g-r project/src/app_backup.py && ls -l project/src/app_backup.py'
  run 'chown alice:alice project/README.md && ls -l project/README.md'
  run 'umask'
  echo "# ---- Processes ----"
  run 'sleep 300 & echo "started PID $!"'
  run 'ps aux --sort=-%mem | head -5'
  run 'pgrep -a sleep'
  run 'top -b -n 1 | head -7'
  run 'kill %1 2>/dev/null || pkill sleep; pgrep sleep || echo "sleep killed"'
  echo "# ---- System info ----"
  run 'uname -a'
  run 'cat /etc/os-release | head -2'
  run 'uptime'
  run 'free -h'
  run 'df -h /'
  run 'du -sh /usr/bin /etc'
  run 'whoami; hostname; id'
  echo "# ---- Archives ----"
  run 'tar -czf project.tar.gz project && ls -lh project.tar.gz'
  run 'tar -tzf project.tar.gz | head -4'
  echo "# ---- Networking basics ----"
  run 'ip -brief addr'
  run 'ss -tuln | head -5'
  echo "# ---- Help & history ----"
  run 'which ls; type cd'
  run 'man -f ls 2>/dev/null || ls --help | head -2'
fi
