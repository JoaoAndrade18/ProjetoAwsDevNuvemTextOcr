import uuid
from django.db import models

class Job(models.Model):
    STATUS_CHOICES = [
        ("PENDING", "PENDING"),
        ("PROCESSING", "PROCESSING"),
        ("DONE", "DONE"),
        ("ERROR", "ERROR"),
        ("EXPIRED", "EXPIRED"),
    ]
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    name = models.CharField(max_length=160)
    status = models.CharField(max_length=16, choices=STATUS_CHOICES, default="PENDING")
    created_at = models.DateTimeField(auto_now_add=True)
    sqs_retention_deadline = models.DateTimeField(null=True, blank=True)

    def __str__(self):
        return f"{self.id} - {self.name} [{self.status}]"

class JobItem(models.Model):
    STATUS_CHOICES = [
        ("PENDING", "PENDING"),
        ("PROCESSING", "PROCESSING"),
        ("DONE", "DONE"),
        ("ERROR", "ERROR"),
    ]
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    job = models.ForeignKey(Job, related_name="items", on_delete=models.CASCADE)
    s3_key = models.CharField(max_length=512)
    status = models.CharField(max_length=16, choices=STATUS_CHOICES, default="PENDING")
    created_at = models.DateTimeField(auto_now_add=True)
    ocr_text = models.TextField(blank=True, null=True)
    error_msg = models.TextField(null=True, blank=True)

    def __str__(self):
        return f"item:{self.id} job:{self.job_id} {self.status}"
    
    
