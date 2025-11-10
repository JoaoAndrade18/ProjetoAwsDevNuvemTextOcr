from datetime import datetime, timedelta
from django.conf import settings

def retention_deadline_from_now() -> datetime:
    return datetime.utcnow() + timedelta(seconds=settings.SQS_RETENTION_SECONDS)
