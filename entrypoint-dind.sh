#!/bin/bash
# Entrypoint for DIND (Docker-in-Docker) mode
# Runs the OOBE setup and drops into an interactive zsh shell

# Run OOBE if this is the first time (playground doesn't exist yet)
if [ ! -d "/home/eda/playground" ]; then
    /etc/oobe_linux.sh
fi

# If running interactively (with -it), drop into zsh
# Otherwise, keep container running (for -d mode)
if [ -t 0 ]; then
    exec zsh -l
else
    exec sleep infinity
fi
