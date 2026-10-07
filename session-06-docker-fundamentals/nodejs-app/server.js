const http = require("http");
const PORT = process.env.PORT || 3000;

http.createServer((req, res) => {
  res.writeHead(200, { "Content-Type": "text/html" });
  res.end("<h1>Hello World from Node.js!</h1>");
}).listen(PORT, () => console.log(`Node.js app listening on ${PORT}`));
