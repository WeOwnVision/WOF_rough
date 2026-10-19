# Multi-stage production container for W.O.F News Intelligence API
FROM python:3.11-slim AS builder

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

FROM python:3.11-slim

WORKDIR /app
COPY --from=builder /root/.local /root/.local
ENV PATH=/root/.local/bin:$PATH
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

# Persistent volume for SQLite FTS5 database (wof_state.db)
RUN mkdir -p /data
ENV DATABASE_URL="sqlite+aiosqlite:////data/wof_state.db"
VOLUME ["/data"]

COPY . .

EXPOSE 8000

# Runs single worker Uvicorn with proxy headers enabled for Render, Fly.io, or Railway
CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1", "--proxy-headers", "--forwarded-allow-ips=*"]
