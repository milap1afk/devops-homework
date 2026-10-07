#!/usr/bin/env bash
# Runs sysinfo.sh on a clean Ubuntu 24.04 box as user "student" and records output.txt.
# Usage (on the host): ./run-in-docker.sh
if [ ! -f /.dockerenv ]; then
  docker run --rm -i --hostname devops-lab -v "$PWD":/hw ubuntu:24.04 bash /hw/run-in-docker.sh \
    | tr -d '\r' > output.txt
  cat output.txt; exit
fi
useradd -m -s /bin/bash student
install -o student -m 755 /hw/sysinfo.sh /home/student/sysinfo.sh
cat > /tmp/demo <<'X'
cd ~
echo '$ ./sysinfo.sh'; ./sysinfo.sh; echo
echo '$ ls -l linux_report'; ls -l linux_report; echo
echo '$ cat linux_report/processes.txt'; cat linux_report/processes.txt
X
(sleep 2; echo linux_report) | script -qec "runuser -u student -- bash /tmp/demo" /dev/null
