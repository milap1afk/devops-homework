// Equivalent of the Kubernetes Basics tutorial image (gcr.io/k8s-minikube/kubernetes-bootcamp),
// rebuilt because that image is no longer available and v2 is amd64-only.
const http = require("http");
const os = require("os");
const VERSION = process.env.VERSION || "1";
const start = new Date();
let requests = 0;

http.createServer((req, res) => {
  requests++;
  console.log(`Running On: ${os.hostname()} | Total Requests: ${requests} | App Uptime: ${(new Date() - start) / 1000} seconds | Log Time: ${new Date()}`);
  res.end(`Hello Kubernetes bootcamp! | Running on: ${os.hostname()} | v=${VERSION}\n`);
}).listen(8080, () => console.log(`Kubernetes Bootcamp App Started At: ${start} | Running On:  ${os.hostname()}`));
