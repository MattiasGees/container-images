FROM ubuntu:24.04 

RUN apt-get update && apt-get install -y \
    openssl \
    vim \
    unzip \
    wget \
    curl \
 && rm -rf /var/lib/apt/lists/*
