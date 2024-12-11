FROM ubuntu:24.04 

RUN apt-get update && apt-get install -y \
    openssl \
    vim \
    unzip \
    wget \
    curl \
    jq \
 && rm -rf /var/lib/apt/lists/*
