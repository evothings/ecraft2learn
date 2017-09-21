# eCraft2Learn


# Raspbian Stretch

    wget http://downloads.raspberrypi.org/raspbian/images/raspbian-2017-09-08/2017-09-07-raspbian-stretch.zip
    unzip 2017-09-07-raspbian-stretch-lite.zip
    sudo dd bs=4M if=2017-09-07-raspbian-stretch-lite.img of=/dev/mmcblk0
## Make sure it was written

    sudo dd bs=4M if=/dev/mmcblk0 of=from-sd-card.img
    sudo truncate --reference 2017-09-07-raspbian-stretch-lite.img from-sd-card.img
    diff -s from-sd-card.img 2017-09-07-raspbian-stretch-lite.img
    rm from-sd-card.img

## Boot Rpi
Put a file called "ssh" onto the sdcard. Insert into Rpi, connect ethernet wire, connect micro USB for power.

    touch /media/<blabla>/ssh
    sudo umount /media/<blabla>

# Login remotely
    ssh pi@raspberrypi.local "raspberry"
Or if prepped already:
    
    ssh pi@sbip.local   "12finger"

# Configure

    sudo raspi-config

* Change hostname to SBIP
* Enable SSH (under Interfacing options)

# Arduino bot

## Installing VerneMQ
VerneMQ is a very solid MQTT server written in Erlang. It runs just fine on Raspbian, but we need to build it from source and apply a tiny tweak. Another popular MQTT server is Mosquitto, but we have had some odd silent crashes using Mosquitto which may be related to issues in libwebsocket (and not in Mosquitto itself), but either way I prefer VerneMQ. **Any MQTT server would of course work just fine.**

### Installing Erlang
We use proper Debian repositories for this:

    wget https://packages.erlang-solutions.com/erlang-solutions_1.0_all.deb
    sudo dpkg -i erlang-solutions_1.0_all.deb
    sudo apt-get update
    sudo apt-get install erlang

### Building VerneMQ
Building VerneMQ is easy:

    git clone git://github.com/erlio/vernemq
    cd vernemq
    make rel

...giving up on VerneMQ for a while, issues to make it on Raspbian Jessie at least...

## Installing Nim
Arduinobot is written in Nim, a modern high performance language that produces small and fast binaries. We first need to install Nim. 
### Linux
Install Nim, easiest done using [choosenim](https://github.com/dom96/choosenim) on a Linux machine:

    curl https://nim-lang.org/choosenim/init.sh -sSf | sh

That will install the `nim` compiler and the `nimble` package manager.

### Raspbian
On Raspbian we need to install nim in a more manual fashion:

    wget https://nim-lang.org/download/nim-0.17.2.tar.xz
    tar xf nim-0.17.2.tar.xz 
    cd nim-0.17.2/
    sh build.sh
    bin/nim c koch
    ./koch tools

Finally we add this to ~/.profile

    export PATH=$PATH:~/nim-0.17.2/bin:~/.nimble/bin

Then we have the `nim` compiler and the `nimble` package manager.

## How to build Arduinobot
### Prerequisites
First we need to compile the Paho C library for communicating with MQTT:

    git clone https://github.com/eclipse/paho.mqtt.c.git
    cd paho.mqtt.c
    make
    sudo make install
    sudo ldconfig

### Building
Enter the `arduinobot` directory and build `arduinobot` using `nimble install`:

    cd arduinobot
    nimble install

## How to run
Arduinobot is a server and only needs an MQTT server to connect to in order to function:

    arduinobot -u:<username> -p:<password> tcp://<someserver>:1883

If successful it should look something like the following:

# VerneMQ


## How to work on the code

I recommend installing VSCode and the Nim extension for it.

