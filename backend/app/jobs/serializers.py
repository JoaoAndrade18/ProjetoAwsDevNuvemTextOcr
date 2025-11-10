from rest_framework import serializers
from .models import Job, JobItem

class JobItemSerializer(serializers.ModelSerializer):
    class Meta:
        model = JobItem
        fields = ["id", "s3_key", "status", "created_at", "ocr_text", "error_msg"]

class JobSerializer(serializers.ModelSerializer):
    total_items = serializers.IntegerField(read_only=True)
    done_items = serializers.IntegerField(read_only=True)

    class Meta:
        model = Job
        fields = [
            "id", "name", "status", "created_at", "sqs_retention_deadline",
            "total_items", "done_items"
        ]

class JobDetailSerializer(JobSerializer):
    items = JobItemSerializer(many=True, read_only=True)

    class Meta(JobSerializer.Meta):
        fields = JobSerializer.Meta.fields + ["items"]
