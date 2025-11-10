import os
from pathlib import Path
from datetime import timedelta

BASE_DIR = Path(__file__).resolve().parent.parent

from dotenv import load_dotenv
load_dotenv(BASE_DIR / ".env")  # carrega backend/.env se existir

SECRET_KEY = os.getenv("DJANGO_SECRET_KEY", "dev-key")
DEBUG = os.getenv("DEBUG", "1") == "1"
ALLOWED_HOSTS = ["*"]

INSTALLED_APPS = [
    "django.contrib.contenttypes",
    "django.contrib.auth",
    "django.contrib.sessions",
    "django.contrib.staticfiles",
    "rest_framework",
    "app.jobs",
]

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],                 # opcionalmente, pastas de templates
        "APP_DIRS": True,           # <- OBRIGATÓRIO para achar templates de apps
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.debug",
                "django.template.context_processors.request",  # <- OBRIGATÓRIO
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
]

ROOT_URLCONF = "app.urls"
WSGI_APPLICATION = "app.wsgi.application"

# DB: usa Postgres via envs (RDS). Sem envs → SQLite para dev rápido.
if os.getenv("RDS_HOST"):
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.postgresql",
            "HOST": os.getenv("RDS_HOST"),
            "PORT": int(os.getenv("RDS_PORT", "5432")),
            "NAME": os.getenv("RDS_DB", "ocrjobs"),
            "USER": os.getenv("RDS_USER", "ocruser"),
            "PASSWORD": os.getenv("RDS_PASSWORD", "password"),
            "CONN_MAX_AGE": 60,
            "OPTIONS": {
                "sslmode": os.getenv("RDS_SSLMODE", "require")
            },
        }
    }
else:
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.sqlite3",
            "NAME": BASE_DIR / "dev.sqlite3",
        }
    }

STATIC_URL = "/static/"
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

REST_FRAMEWORK = {
    "DEFAULT_PAGINATION_CLASS": "rest_framework.pagination.PageNumberPagination",
    "PAGE_SIZE": 20,
}

# AWS / Integrações
AWS_REGION = os.getenv("AWS_REGION", "us-east-1") 
S3_BUCKET = os.getenv("S3_BUCKET", "ocr-aws-nuvem-bucket")
SQS_QUEUE_URL = os.getenv("SQS_QUEUE_URL", "")
DDB_TABLE_LOGS = os.getenv("DDB_TABLE_LOGS", "ocr-aws-crud-logs")

# Regras de job
SQS_RETENTION_SECONDS = int(os.getenv("SQS_RETENTION_SECONDS", "172800"))  # 2 dias
