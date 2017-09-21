# eCraft2Learn

# Arduino bot

## How to build

Install Nim, easiest done using [choosenim](https://github.com/dom96/choosenim) on a Linux machine:

    curl https://nim-lang.org/choosenim/init.sh -sSf | sh

That will install the `nim` compiler and the `nimble` package manager.

Then enter the `arduinobot` directory and build:

    cd arduinobot
    nimble install

## How to run
Arduinobot is a server and only needs an MQTT server to connect to in order to function:

    arduinobot -u:<username> -p:<password> tcp://<someserver>:1883

## How to work on the code

I recommend installing VSCode and the Nim extension for it.

