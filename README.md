proxydriver
===========

Automatically set system proxy from network connection

This is a fork of the original proxydriver script currently maintained 
by Julien Blitte.

Proxydriver is a script  which sets Gnome/Kde proxy settings using
Network Manager's dispatcher. Each network connection triggers a
reconfiguration of the Gnome/Kde proxy, based on the network profile 
name.

To install this file, place it in directory (with +x mod):
/etc/NetworkManager/dispatcher.d

For each new SSID, after a first connection, complete the generated file
/etc/proxydriver.d/<ssid_name>.conf and then re-connect to AP, and the 
proxy should be set.

Original home page: http://marin.jb.free.fr/proxydriver/
Original Sourceforge site: http://sourceforge.net/projects/proxydriver/

