#!/usr/bin/env bash
# Session 7 demo: multi-stage Docker build (Task 1) + deploying Node.js, Python and Java apps (Task 3).
# Usage: ./demo.sh > output.txt      (screenshots are written to screenshots/)
cd "$(dirname "$0")"
run() { echo "\$ $*"; eval "$@" 2>&1; echo; }
# show only the step lines of a BuildKit build, not every progress line
build() { echo "\$ docker build $*"; docker build --progress=plain "$@" 2>&1 | grep -E '^#[0-9]+ \[|naming to|ERROR|error' | sed 's/^#[0-9]* //' | uniq; echo; }
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
browser() { "$CHROME" --headless=new --disable-gpu --hide-scrollbars --window-size=900,300 --screenshot="screenshots/$2" "$1" >/dev/null 2>&1; }

# wait until an app answers on a host port (npm/JVM start-up can take several seconds)
waitfor() { local i; for i in $(seq 1 90); do curl -s -o /dev/null "http://localhost:$1" && break; sleep 1; done; echo "# port $1 answered after ~${i}s"; echo; }

CLONE=${TMPDIR:-/tmp}/s7-devops-heros
NAMES="s7-multistage s7-nodejs s7-python s7-java"
cleanup() { docker rm -f $NAMES >/dev/null 2>&1; }
cleanup; rm -rf "$CLONE"

echo "################ Task 1: clone the repository ################"
run "git clone --depth 1 https://github.com/Nency-Ravaliya/devops-heros $CLONE"
run "ls $CLONE/session6-7-docker/multi-stage-dockerfile"
run "cat $CLONE/session6-7-docker/multi-stage-dockerfile/Dockerfile"
run "cat $CLONE/session6-7-docker/multi-stage-dockerfile/server.js"
# keep a copy in this folder so the repo is self-contained
cp "$CLONE"/session6-7-docker/multi-stage-dockerfile/{Dockerfile,package.json,server.js} multi-stage-dockerfile/
run "diff -r -x Dockerfile.single $CLONE/session6-7-docker/multi-stage-dockerfile multi-stage-dockerfile && echo 'local copy identical to the cloned files'"

echo "################ Task 1: build with the multi-stage Dockerfile ################"
build -t s7-multistage:1.0 "$CLONE/session6-7-docker/multi-stage-dockerfile"

echo "################ Task 1: run it on port 8080 ################"
echo "# the app listens on 3000 inside the container -> publish it as host port 8080"
run 'docker run -d --name s7-multistage -p 8080:3000 s7-multistage:1.0'
waitfor 8080
run 'docker ps --filter name=s7-multistage --format "table {{.ID}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}\t{{.Names}}"'
run 'docker port s7-multistage'
run 'docker logs s7-multistage'

echo "################ Task 1: access the application ################"
run 'curl -s http://localhost:8080; echo'
run 'curl -sI http://localhost:8080 | head -4'
run 'curl -s http://localhost:8080 | grep -io "Hello World from Docker multi-stage build" && echo "VERIFIED: response contains the expected text"'
browser http://localhost:8080 multistage-browser-8080.png
echo "# browser screenshot saved: screenshots/multistage-browser-8080.png"
echo
echo "# what is inside the final image: only package*.json, server.js and production node_modules"
run 'docker exec s7-multistage ls /app'

echo "################ Single-stage vs multi-stage image size ################"
build -t s7-single:1.0 -f multi-stage-dockerfile/Dockerfile.single multi-stage-dockerfile
build -t s7-java-single:1.0 -f apps/java-app/Dockerfile.single apps/java-app
build -t s7-java:1.0 apps/java-app
run 'docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | grep -E "REPOSITORY|^s7-(multistage|single|java)"'
run "docker image inspect -f '{{.RepoTags}} {{.Size}} bytes' s7-multistage:1.0 s7-single:1.0 s7-java:1.0 s7-java-single:1.0"
run "docker history --format '{{.CreatedBy}} => {{.Size}}' s7-multistage:1.0 | head -8"
run "docker history --format '{{.CreatedBy}} => {{.Size}}' s7-single:1.0 | head -6"
echo "# where the node difference comes from: files in /app and the npm cache (KB)"
run "docker run --rm s7-single:1.0 sh -c 'ls -A /app | tr \"\\n\" \" \"; echo; du -sk /root/.npm'"
run "docker run --rm s7-multistage:1.0 sh -c 'ls -A /app | tr \"\\n\" \" \"; echo; du -sk /root/.npm'"
echo "# java: is the compiler (javac) in the final image?"
run "docker run --rm s7-java-single:1.0 sh -c 'command -v javac || echo no javac'"
run "docker run --rm s7-java:1.0 sh -c 'command -v javac || echo no javac'"

echo "################ Task 3: deploy Node.js, Python and Java apps ################"
build -t s7-nodejs:1.0 apps/nodejs-app
build -t s7-python:1.0 apps/python-app
run 'docker run -d --name s7-nodejs -p 3001:3000 s7-nodejs:1.0'
run 'docker run -d --name s7-python -p 5001:5000 s7-python:1.0'
run 'docker run -d --name s7-java   -p 8081:8080 s7-java:1.0'
for p in 3001 5001 8081; do waitfor $p; done
run 'docker ps --filter name=s7- --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"'
run 'curl -s http://localhost:8080; echo'
run 'curl -s http://localhost:3001; echo'
run 'curl -s http://localhost:5001; echo'
run 'curl -s http://localhost:8081; echo'
browser http://localhost:3001 nodejs-browser-3001.png
browser http://localhost:5001 python-browser-5001.png
browser http://localhost:8081 java-browser-8081.png
echo "# browser screenshots saved: screenshots/{nodejs-browser-3001,python-browser-5001,java-browser-8081}.png"
echo
run 'docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | grep -E "REPOSITORY|^s7-"'

echo "################ Cleanup ################"
run "docker rm -f $NAMES"
run 'docker rmi s7-multistage:1.0 s7-single:1.0 s7-java-single:1.0 s7-java:1.0 s7-nodejs:1.0 s7-python:1.0'
rm -rf "$CLONE"
