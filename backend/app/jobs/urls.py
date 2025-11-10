from django.urls import path
from .views import JobsView, JobDetailView

urlpatterns = [
    path("jobs/", JobsView.as_view()),
    path("jobs/<uuid:job_id>/", JobDetailView.as_view()),
]
