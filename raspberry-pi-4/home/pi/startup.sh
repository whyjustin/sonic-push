#!/bin/sh

sleep 5
SOUND_CARD=$(aplay -l | sed -nE 's/^.*card (.): CODEC \[USB Audio CODEC\].*$/\1/p')
printf "pcm."'!'"default {\n  type hw\n  card ${SOUND_CARD}\n}" > /home/pi/.asoundrc
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/dbus/system_bus_socket 
killall jackd
Xvfb :1 & xvfb-run /home/pi/sonic-pi/bin/sonic-pi 2 >/dev/null

