FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04
ENV DEBIAN_FRONTEND=noninteractive PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
RUN apt-get update && apt-get install -y --no-install-recommends python3 python3-pip ffmpeg git curl ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ARG PIP_MIRROR=auto
ARG TZ=Etc/UTC
ENV PIP_MIRROR=${PIP_MIRROR} TZ=${TZ}
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
COPY scripts/pip_mirror.sh scripts/pip_mirror.sh
COPY requirements.txt .
RUN source scripts/pip_mirror.sh && configure_pip_mirror && python3 -m pip install --no-cache-dir -r requirements.txt
COPY . .
EXPOSE 8000
CMD ["python3", "-m", "uvicorn", "gateway.main:app", "--host", "0.0.0.0", "--port", "8000"]
