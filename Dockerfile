FROM nvidia/cuda:12.8.0-devel-ubuntu24.04 AS build

ARG N_JOBS
ARG CUDA_ARCH

RUN apt-get update && apt-get install -y cmake

# ========================================
# Build llama.cpp
# ========================================

COPY ./volume/llama.cpp /root/volume/llama.cpp
WORKDIR /root/volume/llama.cpp

# The symbolic link is required since llama.cpp searches for libcuda.so.1 at linking time
# Tests and examples are turned off so that every install rule has a built artifact
RUN \
 ln -s /usr/local/cuda/lib64/stubs/libcuda.so /usr/local/cuda/lib64/stubs/libcuda.so.1 && \
 cmake -B build \
  -DGGML_CUDA=ON \
  -DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCH} \
  -DLLAMA_BUILD_TESTS=OFF \
  -DLLAMA_BUILD_EXAMPLES=OFF && \
 cmake --build build --config Release -j ${N_JOBS} && \
 cmake --install build && \
 ldconfig

# ========================================
# Build whisper.cpp
# ========================================

COPY ./volume/whisper.cpp /root/volume/whisper.cpp
WORKDIR /root/volume/whisper.cpp

# -rpath-link lets ld resolve libggml-cuda.so's libcuda.so.1 dependency against the stub
RUN \
 apt-get update && apt-get install -y libsdl2-dev && \
 cmake -B build \
  -DWHISPER_SDL2=ON \
  -DWHISPER_USE_SYSTEM_GGML=ON \
  -DWHISPER_USE_SYSTEM_LLAMA=ON \
  -DCMAKE_EXE_LINKER_FLAGS=-Wl,-rpath-link,/usr/local/cuda/lib64/stubs \
  -DBUILD_SHARED_LIBS=OFF && \
 cmake --build build --config Release -j ${N_JOBS} --target whisper-cli whisper-server whisper-stream && \
 cp build/bin/whisper-cli build/bin/whisper-server build/bin/whisper-stream /usr/local/bin/

RUN apt-get update && apt-get install curl

# ========================================
# Microphone
# ========================================

# SDL 2.30's native PulseAudio capture never receives data from the host's PulseAudio server (zero callbacks)
# So SDL is routed through ALSA, and ALSA through the Pulse plugin
RUN \
 apt-get update && apt-get install -y libasound2-plugins && \
 printf 'pcm.!default { type pulse }\nctl.!default { type pulse }\n' > /etc/asound.conf
ENV SDL_AUDIODRIVER=alsa

WORKDIR /root/volume
