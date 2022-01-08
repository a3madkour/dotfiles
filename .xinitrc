#!/usr/bin/env bash

xscreensaver &
~/.config/polybar/launch.sh &
sleep 0.5;
exec xmonad
#exec awesome
