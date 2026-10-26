# speech2action
Agentic microphone below 4GB of memory. 

This is a reinventing-the-wheel project. It doesn't provide innovative functionalities, it is mostly a playground/exercising project.

Currently only supports CUDA. Requires CUDA drivers and nvidia-container-toolkit on the host machine. Everything else is self-contained in the container.

## Setup
1. Clone the repo
    ```bash
    git clone
    ```
    The repo already bundles llama.cpp
2. Copy the ```.env``` template

    ```bash
    cp .env.example .env
    ```

    then edit it, filling it with the user- and machine- specific arguments.

3. Build the container and llama.cpp:
    
    ```bash
    make build
    ```

## Makefile targets
Base functionalities can be handled via the Makefile.
Use the following targets by typing ```make <target>``` from the root of the repository.

The available targets are:

- bench 
```make bench CMD=<what_you_would_type_after llama-server>``` 
allows to benchmark a model, measuring:
    - prefill t/s over a 500 tokens prompt
    - decode t/s over 256 tokens
    - tok/J considering the whole laptop power
    - average power W considering the whole laptop power
    - CPU temperature, max and idle
    - GPU temperature, max and idle


