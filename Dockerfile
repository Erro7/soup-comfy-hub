FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
ARG PIP_MIRROR=auto
ARG TZ=Etc/UTC
ENV PIP_MIRROR=${PIP_MIRROR} TZ=${TZ}
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
COPY scripts/pip_mirror.sh scripts/pip_mirror.sh
COPY studio_frontend/requirements.txt requirements.txt
RUN source scripts/pip_mirror.sh && configure_pip_mirror && pip install --no-cache-dir -r requirements.txt
COPY studio_frontend/app.py app.py
EXPOSE 7860
CMD ["python", "-m", "uvicorn", "app:app", "--host", "0.0.0.0", "--port", "7860"]
