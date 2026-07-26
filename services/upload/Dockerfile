# Build context = services/  →  docker build -f services/upload/Dockerfile -t upload:dev services/
FROM python:3.12-slim AS builder
WORKDIR /w
COPY _base ./_base
RUN pip install --no-cache-dir --prefix=/install ./_base uvicorn

FROM python:3.12-slim
RUN useradd -u 10001 -m appuser
WORKDIR /app
COPY --from=builder /install /usr/local
COPY upload/app ./app
USER 10001
EXPOSE 8080
CMD ["python", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
