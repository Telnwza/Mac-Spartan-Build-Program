# Third-party tools and references

Spartan Build & Program is MIT licensed. It invokes separately installed tools;
its MIT license does not relicense those tools or their installers.

| Tool | Use | Project / terms |
|---|---|---|
| openFPGALoader | JTAG detection and FPGA programming on the host Mac | [Project and license](https://github.com/trabucayre/openFPGALoader) |
| filmil/vivado-docker | External instructions for building a Vivado container | [Project and license](https://github.com/filmil/vivado-docker) |
| AMD Vivado | Synthesis, implementation and bitstream generation inside the container | [AMD downloads](https://www.amd.com/en/support/downloads/adaptive-socs-and-fpgas/development-tools/2025-2.html) and the terms accompanying the user's installer |
| Docker Desktop | Runs the Linux container on macOS | [Docker terms](https://www.docker.com/legal/docker-subscription-service-agreement/) |
| Homebrew | Optional installation method for openFPGALoader | [Homebrew](https://brew.sh) |

The app and source archives do not bundle these tools, Vivado installers, Docker
images, or upstream source files. The Rosetta startup command uses the optional
`/opt/udev_stub.so` already present in compatible upstream images; this project
does not distribute that library.

Board names, FPGA part names, macOS and tool names identify compatible hardware
and software; they do not imply endorsement by their respective owners.
