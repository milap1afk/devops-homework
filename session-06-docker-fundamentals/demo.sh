#!/usr/bin/env bash
# Builds, runs and verifies all six Hello World apps. Writes output.txt.
set -e
run() { echo "\$ $*"; eval "$@" 2>&1; echo; }
# name : host port : container port
APPS="nodejs-app:3000:3000 python-app:5001:5000 java-app:8080:8080 Apache-app:8081:80 React-app:8082:80 nginx-app:8083:80"

for a in $APPS; do docker rm -f "${a%%:*}" >/dev/null 2>&1 || true; done
for a in $APPS; do
  IFS=: read -r name hport cport <<< "$a"
  img=$(echo "$name" | tr 'A-Z' 'a-z')
  echo "################ $name ################"
  echo "\$ docker build -t $img:1.0 ./$name"
  docker build -t "$img:1.0" "./$name" 2>&1 | grep -E '^#[0-9]+ \[|naming to|DONE' | tail -4
  echo
  run "docker run -d --name $name -p $hport:$cport $img:1.0"
done
sleep 5
run 'docker ps --filter name=-app --format "table {{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}"'
for a in $APPS; do
  IFS=: read -r name hport cport <<< "$a"
  if [ "$name" = React-app ]; then
    # React renders in the browser; curl shows the shell page that loads the bundle
    run "curl -s http://localhost:$hport | grep -o '<div id=\"root\"></div>\|assets/index-[a-zA-Z0-9_-]*\.js'"
    run "curl -s http://localhost:$hport/\$(curl -s http://localhost:$hport | grep -o 'assets/index-[a-zA-Z0-9_-]*\.js') | grep -o 'Hello World from React!'"
  else
    run "curl -s http://localhost:$hport | grep -o 'Hello World[^<]*'"
  fi
done
run 'docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | grep -E "REPOSITORY|app"'
