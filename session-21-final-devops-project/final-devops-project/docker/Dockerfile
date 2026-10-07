# Build context: final-devops-project/   ->   docker build -f docker/Dockerfile -t kirana-final .
FROM python:3.12-slim AS deps
WORKDIR /install
COPY application/requirements.txt .
RUN pip install --no-cache-dir --prefix=/install/pkgs -r requirements.txt

FROM python:3.12-slim
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION} PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN apt-get update && apt-get upgrade -y && rm -rf /var/lib/apt/lists/* \
 && useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin appuser
COPY --from=deps /install/pkgs /usr/local
WORKDIR /app
COPY application/app.py .
USER 10001
EXPOSE 8000
# 1 worker + threads keeps Prometheus metrics in a single process
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "1", "--threads", "4", "--access-logfile", "-", "app:create_app()"]
