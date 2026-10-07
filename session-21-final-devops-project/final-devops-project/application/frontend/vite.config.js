import { defineConfig } from "vite";

// `npm run dev` proxies /api to a backend on localhost:8000
export default defineConfig({
  server: { proxy: { "/api": "http://localhost:8000" } },
});
