FROM python:3.12-slim AS builder 
WORKDIR /w 
COPY _base ./_base 
RUN pip install --no-cache-dir --prefix=/install ./_base 

FROM python:3.12-slim 
RUN apt-get update && apt-get install -y --no-install-recommends ffmpeg && rm -rf /var/lib/apt/lists/*
RUN useradd -u 10001 -m appuser 
WORKDIR /app 
COPY --from=builder /install /usr/local 
COPY transcode-worker/app ./app 
USER 10001 
CMD ["python", "-m", "app.main"]