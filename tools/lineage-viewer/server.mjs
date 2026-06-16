import { createServer } from "node:http";
import { createReadStream, existsSync, statSync } from "node:fs";
import { extname, join, normalize, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = fileURLToPath(new URL(".", import.meta.url));
const repoRoot = resolve(__dirname, "../..");
const portArg = process.argv.find((arg) => arg.startsWith("--port="));
const port = Number(portArg?.slice("--port=".length) ?? process.env.PORT ?? 5177);

const contentTypes = new Map([
  [".html", "text/html; charset=utf-8"],
  [".js", "text/javascript; charset=utf-8"],
  [".css", "text/css; charset=utf-8"],
  [".json", "application/json; charset=utf-8"],
  [".svg", "image/svg+xml"],
]);

function send(res, status, body, type = "text/plain; charset=utf-8") {
  res.writeHead(status, {
    "Content-Type": type,
    "Cache-Control": "no-store",
  });
  res.end(body);
}

function resolveStaticPath(urlPath) {
  const requestedPath = urlPath === "/" ? "/tools/lineage-viewer/index.html" : urlPath;
  const decodedPath = decodeURIComponent(requestedPath.split("?")[0]);
  const candidate = normalize(join(repoRoot, decodedPath));

  if (!candidate.startsWith(repoRoot)) {
    return null;
  }

  return candidate;
}

const server = createServer((req, res) => {
  if (!req.url || !["GET", "HEAD"].includes(req.method ?? "")) {
    send(res, 405, "Method not allowed");
    return;
  }

  const filePath = resolveStaticPath(req.url);
  if (!filePath || !existsSync(filePath) || !statSync(filePath).isFile()) {
    send(res, 404, "Not found");
    return;
  }

  const type = contentTypes.get(extname(filePath)) ?? "application/octet-stream";
  res.writeHead(200, {
    "Content-Type": type,
    "Cache-Control": "no-store",
  });

  if (req.method === "HEAD") {
    res.end();
    return;
  }

  createReadStream(filePath).pipe(res);
});

server.listen(port, "127.0.0.1", () => {
  console.log(`Lineage viewer: http://127.0.0.1:${port}/`);
  console.log("Reading: output/lineage.json");
});
