#!/usr/bin/env bash
# Session 4 demo: Linux networking commands, run inside a Linux container (nicolaka/netshoot).
# Usage: ./demo.sh > output.txt
#
# Lab:  docker network s4-net (172.30.4.0/24)
#         s4-box  - nicolaka/netshoot, where every "$ ..." command below runs
#         s4-web  - nginx:alpine web server (target for ping/curl/nc/nmap/ss)
#         s4-nc   - netcat server on port 9000
cd "$(dirname "$0")"
box() { echo "\$ $*"; docker exec s4-box sh -c "$*" 2>&1; echo; }
hostrun() { echo "\$ $*"; eval "$@" 2>&1; echo; }

cleanup() {
  docker rm -f s4-box s4-web s4-nc >/dev/null 2>&1
  docker network rm s4-net >/dev/null 2>&1
}
cleanup
docker pull -q nicolaka/netshoot:latest >/dev/null
docker pull -q nginx:alpine >/dev/null

echo "################ Lab setup (on the Mac host) ################"
hostrun 'docker network create --subnet 172.30.4.0/24 s4-net'
hostrun 'docker run -d --name s4-web --network s4-net nginx:alpine'
hostrun "docker run -d --name s4-nc --network s4-net nicolaka/netshoot sh -c 'echo hello from s4-nc | nc -l -p 9000'"
hostrun 'docker run -d --name s4-box --hostname s4-box --network s4-net nicolaka/netshoot sleep 600'
hostrun "docker network inspect s4-net --format '{{range .Containers}}{{.Name}}={{.IPv4Address}} {{end}}'"
sleep 1
echo "# From here on, every command runs INSIDE the Linux container s4-box"
echo

echo "################ 1. hostname / uname ################"
box 'hostname; hostname -i; uname -sr'

echo "################ 2. ip addr / ip link ################"
box 'ip addr show'
box 'ip -br addr'
box 'ip -br link'

echo "################ 3. ifconfig (legacy, net-tools) ################"
box 'ifconfig eth0'

echo "################ 4. ip route / route -n ################"
box 'ip route'
box 'ip route get 8.8.8.8'
box 'route -n'

echo "################ 5. /etc/resolv.conf and /etc/hosts ################"
box 'cat /etc/resolv.conf'
box 'cat /etc/hosts'
box 'getent hosts s4-web'

echo "################ 6. ping ################"
box 'ping -c 3 s4-web'
box 'ping -c 3 8.8.8.8'
box 'ping -c 2 google.com'

echo "################ 7. ip neigh / arp (layer-2 neighbours) ################"
box 'ip neigh'
box 'arp -n'

echo "################ 8. traceroute / tracepath / mtr ################"
box 'traceroute -n -m 5 -w 1 8.8.8.8'
box 'traceroute -I -n -m 5 -w 1 8.8.8.8'
box 'tracepath -n -m 4 8.8.8.8'
box 'mtr -r -n -c 3 8.8.8.8'

echo "################ 9. nslookup / dig / host (DNS) ################"
box 'nslookup google.com'
box 'nslookup s4-web'
box 'dig example.com'
box 'dig +short google.com MX'
box 'dig +short @1.1.1.1 github.com'
box 'dig +short -x 8.8.8.8 @1.1.1.1'
box 'dig +short s4-web'
box 'host google.com'

echo "################ 10. whois ################"
box 'whois example.com | grep -iE "^(domain|organisation|status|created|changed|source|nserver)" | head -12'

echo "################ 11. curl ################"
box 'curl -sv http://s4-web/ -o /dev/null'
box 'curl -sI https://example.com'
box 'curl -sv https://example.com -o /dev/null 2>&1 | grep -E "Connected to|SSL connection|ALPN|subject:|issuer:|^< HTTP"'
box 'curl -s -o /dev/null -w "dns=%{time_namelookup}s connect=%{time_connect}s tls=%{time_appconnect}s total=%{time_total}s code=%{http_code}\n" https://example.com'

echo "################ 12. ss / netstat (sockets and ports) ################"
echo "# ss inside s4-web's network namespace (sidecar sharing its network) shows nginx listening"
hostrun 'docker run --rm --network container:s4-web nicolaka/netshoot ss -tlnp'
box 'ss -tuln'
box 'timeout 3 nc s4-web 80 >/dev/null & sleep 1; ss -tn; wait'
box 'netstat -rn'
box 'ss -s'

echo "################ 13. nc (netcat) ################"
box 'nc -zv -w 2 s4-web 80'
box 'nc -zv -w 2 s4-web 81'
box 'nc -w 2 s4-nc 9000'
box 'printf "GET / HTTP/1.0\r\nHost: s4-web\r\n\r\n" | nc -w 2 s4-web 80 | head -5'

echo "################ 14. nmap (port scan) ################"
box 'nmap -Pn -p 22,80,443 s4-web'

echo "################ 15. tcpdump (watch the TCP handshake) ################"
box 'timeout 6 tcpdump -i eth0 -n -c 8 tcp port 80 2>&1 & sleep 1; curl -s s4-web >/dev/null; wait'

echo "################ 16. IP addressing and subnetting (ipcalc + python ipaddress) ################"
box 'ipcalc -bnmp 197.23.45.10/24'
box 'ipcalc -bnmp 120.27.1.0/8'
box 'ipcalc -bnmp 172.30.4.2/24'
box 'ipcalc -m 10.1.2.3; ipcalc -m 150.1.2.3; ipcalc -m 200.1.2.3'
docker cp subnet.py s4-box:/tmp/subnet.py >/dev/null 2>&1
box 'python3 /tmp/subnet.py'

echo "################ Cleanup ################"
hostrun 'docker rm -f s4-box s4-web s4-nc'
hostrun 'docker network rm s4-net'
