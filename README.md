# speech2action
Agentic microphone below 4GB of memory.

Currently only supports CUDA.

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

