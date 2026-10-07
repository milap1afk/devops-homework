FROM python:3.12-slim
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION} PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app/app.py .
RUN useradd --uid 10001 --no-create-home appuser
USER 10001
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", "app:create_app()"]
