FROM node:20-alpine
ARG VERSION=1
ENV VERSION=${VERSION}
RUN apk add --no-cache curl
WORKDIR /app
COPY server.js .
EXPOSE 8080
CMD ["node", "server.js"]
