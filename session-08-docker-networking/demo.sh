#!/usr/bin/env bash
# Session 8 demo: container networking, host network, bind mount, overlay network.
# Writes everything it does to stdout; README output comes from:  ./demo.sh > output.txt
run() { echo "\$ $*"; eval "$@" 2>&1; echo; }
cd "$(dirname "$0")"
# clean slate
docker rm -f frontend backend database intruder apache2-host nginx-bind >/dev/null 2>&1
docker network rm frontend-net backend-net isolated-net >/dev/null 2>&1
echo "Hello students" > bind-mount-site/index.html
docker swarm leave --force >/dev/null 2>&1
for i in mysql:8.4 alpine:3.20 nginx:alpine ubuntu/apache2:latest; do docker pull -q $i >/dev/null; done
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
shot() { "$CHROME" --headless=new --disable-gpu --hide-scrollbars --window-size=900,${3:-200} --screenshot="screenshots/$2" "$1" >/dev/null 2>&1; }
mkdir -p screenshots

echo "################ Task 1: container networking ################"
run 'docker network create frontend-net'
run 'docker network create backend-net'
run 'docker network create isolated-net'
run 'docker network ls --filter name=-net'
run 'docker run -d --name database --network backend-net -e MYSQL_ROOT_PASSWORD=devops123 -e MYSQL_DATABASE=shop mysql:8.4'
run 'docker run -d --name backend --network frontend-net alpine:3.20 sleep infinity'
echo "# Attach backend to a SECOND network -> backend is on frontend-net AND backend-net"
run 'docker network connect backend-net backend'
run 'docker run -d --name frontend --network frontend-net nginx:alpine'
run 'docker run -d --name intruder --network isolated-net alpine:3.20 sleep infinity'
run "docker inspect backend --format '{{range \$k, \$v := .NetworkSettings.Networks}}{{\$k}}={{\$v.IPAddress}} {{end}}'"
run "docker network inspect frontend-net --format '{{range .Containers}}{{.Name}} {{end}}'"
run "docker network inspect backend-net --format '{{range .Containers}}{{.Name}} {{end}}'"
run "docker network inspect isolated-net --format '{{range .Containers}}{{.Name}} {{end}}'"
echo "# Waiting for MySQL to accept connections..."
until docker exec database mysqladmin -uroot -pdevops123 ping >/dev/null 2>&1; do sleep 2; done
echo "# frontend -> backend (same network: frontend-net)  => should WORK"
run 'docker exec frontend ping -c 2 backend'
echo "# backend -> database (same network: backend-net)  => should WORK"
run 'docker exec backend ping -c 2 database'
run 'docker exec backend nc -zv -w 3 database 3306'
echo "# frontend -> database (no shared network)  => should FAIL"
run 'docker exec frontend ping -c 2 -W 2 database'
echo "# intruder (isolated-net) -> backend  => should FAIL"
run 'docker exec intruder ping -c 2 -W 2 backend'
run 'docker exec database mysql -uroot -pdevops123 -e "SHOW DATABASES;"'

echo "################ Task 2: host network ################"
run 'docker pull -q ubuntu/apache2:latest'
run 'docker run -d --name apache2-host --network host ubuntu/apache2:latest'
sleep 3
echo "# No -p mapping: with --network host, Apache binds port 80 of the Docker host directly"
run "docker inspect apache2-host --format 'NetworkMode={{.HostConfig.NetworkMode}} PortBindings={{.HostConfig.PortBindings}}'"
echo "# On the Docker host (the Colima Linux VM):"
run "colima ssh -- sh -c 'sudo ss -ltnp | grep \":80 \"'"
run "colima ssh -- curl -s http://localhost:80 | grep -o '<title>.*</title>'"
echo "# And from the Mac (Colima forwards the VM's port 80 to localhost):"
run "curl -s http://localhost:80 | grep -o '<title>.*</title>'"
shot http://localhost:80 task2-apache-host-network.png 700

echo "################ Task 3: bind mount ################"
run 'cat bind-mount-site/index.html'
run 'docker run -d --name nginx-bind -p 8090:80 -v "$PWD/bind-mount-site":/usr/share/nginx/html:ro nginx:alpine'
sleep 2
run 'curl -s http://localhost:8090'
shot http://localhost:8090 task3-before.png
run "docker inspect nginx-bind --format '{{range .Mounts}}{{.Type}}: {{.Source}} -> {{.Destination}} (RW={{.RW}}){{end}}'"
echo "# Edit the file on the HOST only. No restart, no docker cp."
run 'echo "Hello students - updated live from the host at $(date +%H:%M:%S)" > bind-mount-site/index.html'
run 'curl -s http://localhost:8090'
shot http://localhost:8090 task3-after.png
run "docker ps --filter name=nginx-bind --format '{{.Names}} {{.Status}}'"

echo "################ Task 4: overlay network ################"
run 'docker swarm init --advertise-addr 127.0.0.1 >/dev/null 2>&1; docker info --format "Swarm: {{.Swarm.LocalNodeState}}"'
run 'docker network create -d overlay --attachable demo-overlay'
run 'docker network ls --filter driver=overlay'
run "docker network inspect demo-overlay --format 'Driver={{.Driver}} Scope={{.Scope}} Subnet={{range .IPAM.Config}}{{.Subnet}}{{end}}'"
run 'docker service create -q --name web --replicas 2 --network demo-overlay nginx:alpine'
run 'docker service ps web --format "{{.Name}} {{.CurrentState}}"'
run 'docker run --rm --network demo-overlay alpine:3.20 sh -c "nslookup tasks.web 2>/dev/null | grep Address | tail -2; wget -qO- http://web | grep -o \"<title>.*</title>\""'

# cleanup
docker service rm web >/dev/null; sleep 3; docker network rm demo-overlay >/dev/null; docker swarm leave --force >/dev/null
docker rm -f frontend backend database intruder apache2-host nginx-bind >/dev/null
docker network rm frontend-net backend-net isolated-net >/dev/null
echo "Hello students" > bind-mount-site/index.html
