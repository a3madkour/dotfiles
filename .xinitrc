#!/usr/bin/env bash

xscreensaver &
autorandr egypt &
~/.config/polybar/launch.sh &
sleep 2.0;
exec xmonad
#exec awesome
