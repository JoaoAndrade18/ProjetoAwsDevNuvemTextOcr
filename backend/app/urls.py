# backend/app/urls.py
from django.urls import path, include
from django.http import JsonResponse

def health(_request):
    return JsonResponse({"status": "ok"})

urlpatterns = [
    path("health", health),   # /health (sem barra final)
    path("health/", health),  # /health/ (com barra final)
    path("api/", include("app.jobs.urls")),
]
