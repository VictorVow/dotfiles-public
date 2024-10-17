#!/bin/bash

# https://ngrok.com/docs/getting-started

# Check if ngrok is installed
if ! command -v ngrok &> /dev/null
then
    echo "ngrok is not installed. Installing now..."

    # Fetch the ngrok GPG key and add it to the keyring
    curl -s https://ngrok-agent.s3.amazonaws.com/ngrok.asc | sudo gpg --dearmor -o /etc/apt/keyrings/ngrok.gpg

    # Add the ngrok repository to the sources list
    echo "deb [signed-by=/etc/apt/keyrings/ngrok.gpg] https://ngrok-agent.s3.amazonaws.com buster main" | sudo tee /etc/apt/sources.list.d/ngrok.list

    # Update the package list
    sudo apt update

    # Install ngrok
    sudo apt install -y ngrok

    echo "ngrok has been installed."
else
    echo "ngrok is already installed."
fi
