FROM nvidia/cuda:12.8.0-devel-ubuntu24.04 AS build

RUN apt-get update && apt-get install -y cmake

# build for pascal 
COPY ./volume/llama.cpp /root/volume/llama.cpp 
WORKDIR /root/volume/llama.cpp
ARG N_JOBS
RUN cmake -B build \
 -DGGML_CUDA=ON \
 -DCMAKE_CUDA_ARCHITECTURES=61 && \
 cmake --build build --config Release -j ${N_JOBS}  --target llama-server llama-cli llama-bench
