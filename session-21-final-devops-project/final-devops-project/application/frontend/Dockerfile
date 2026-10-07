# ---- Stage 1: build the static site with Node ----
FROM node:22-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts
COPY index.html vite.config.js ./
COPY src ./src
RUN npm run build

# ---- Stage 2: serve it with an unprivileged nginx (runs as uid 101, listens on 8080) ----
FROM nginxinc/nginx-unprivileged:1.29-alpine
USER root
RUN apk upgrade --no-cache          # pull in fixed OS packages (Trivy gate: no fixable HIGH/CRITICAL)
ENV BACKEND_URL=http://backend:8000
COPY nginx.conf.template /etc/nginx/templates/default.conf.template
COPY --from=build /app/dist /usr/share/nginx/html
USER 101
EXPOSE 8080
