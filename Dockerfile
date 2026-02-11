# =========================
# Stage 1: Builder
# =========================
FROM python:3.13-slim AS builder

# Create app directory
RUN mkdir /app
WORKDIR /app

# Python env optimizations
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# System deps (optional but safe for Django)
RUN apt-get update && apt-get install -y \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Upgrade pip
RUN pip install --upgrade pip

# Copy requirements first (cache-friendly)
COPY requirements.txt .

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy project files
COPY . .

# ---- collect static files ----
# Ensure Django doesn't need DB access
ENV DJANGO_SETTINGS_MODULE=primechoice.settings
ENV DEBUG=False

RUN python manage.py collectstatic --noinput


# =========================
# Stage 2: Production
# =========================
FROM python:3.13-slim

# Create non-root user
RUN useradd -m -r appuser && \
    mkdir /app && \
    chown -R appuser /app

# Copy installed python packages
COPY --from=builder /usr/local/lib/python3.13/site-packages/ /usr/local/lib/python3.13/site-packages/
COPY --from=builder /usr/local/bin/ /usr/local/bin/

# Copy app code + collected static files
COPY --from=builder /app /app

WORKDIR /app

# Python env optimizations
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Switch to non-root user
USER appuser

EXPOSE 8000

# Start Gunicorn
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "3", "primechoice.wsgi:application"]

