# Sonic Push

Sonic Pi scripts to use Ableton Push in a DAWless workflow. Using SCM to track changes. Using GitHub to share.

# Sonic Pi Compatibility

## Raspberry Pi

Sonic Push is perfomant running on a Raspberry Pi 4 with v3.2-dev. There is a good post on how to install
3.2-dev on Raspbian Buster called [Building SP3.2dev from source on a Pi4](https://in-thread.sonic-pi.net/t/building-sp3-2dev-from-source-on-a-pi4/2645).
Note a minor mistake in script where

```
cp utils/ruby_help.tmpl ruby_help.h
```

should read 

```
cp utils/ruby_help.tmpl utils/ruby_help.h
```

I use systemd to run Sonic Pi in headless mode from the command line. All the configuration files are available
in the raspberry-pi-4 folder. 

## OSX

All the features necessary to run Sonic Push should be available in Sonic Pi v3.2. I've had [issues using
x3.2-beta with OSX](https://github.com/samaaron/sonic-pi/issues/2101) and therefore am running a custom version
of v3.1 with some features ported from v3.2. Patches for this custom version are available in sonic-pi-patches.

# Development

I found the best way to develop is to use the buffer.rb file and load it through your IDE or copy into a Sonic Pi buffer.
Note the line:

```
load 'home/pi/sonic-push/module.rb'
```

This can be used to edit a particular module without having to reload Sonic Pi.

# Apologies

I would like to formally apologize for this code. What seemed like a good idea has gone well out of hand.
There be dragons and spaghetti everywhere.
