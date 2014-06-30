#!/bin/bash

# This script will set gnome/KDE/shell proxy configuration for each SSID
# Version: 1.61
#
# Current script maintainer:
# - Julien Blitte            <julien.blitte at gmail.com>
#
# Authors and contributors:
# - Berend Deschouwer        <berend.deschouwer at ucs-software.co.za>
# - Ivan Gusev               <ivgergus at gmail.com>
# - Jean-Baptiste Masurel    <jbmasurel at gmail.com>
# - Julien Blitte            <julien.blitte at gmail.com>
# - Milos Pejovic            <pejovic at gmail.com>
# - Sergiy S. Kolesnikov     <kolesnik at fim.uni-passau.de>
# - Tom Herrmann             <mail at herrmann-tom.de>
# - Ulrik Stervbo            <ulrik.stervbo at gmail.com>
#
# To install this file, place it in directory (with +x mod):
# /etc/NetworkManager/dispatcher.d
#
# For each new SSID, after a first connection, complete the genreated file
# /etc/proxydriver.d/<ssid_name>.conf and then re-connect to AP, proxy is now set!
#

conf_dir='/etc/proxydriver.d'
log_tag='proxydriver'
running_device='/var/run/proxydriver.device'
proxy_env='/var/lib/proxydriver/environment.sh'

logger -p user.debug -t $log_tag "script called: $*"

# vpn disconnection handling
if [ "$2" == "up" ]
then
	echo "$1" > "$running_device"
elif [ "$2" == "vpn-down" ]
then
	set -- `cat "$running_device"` "up"
fi

if [ "$2" == "up" -o "$2" == "vpn-up" ]
then
	logger -p user.notice -t $log_tag "interface '$1' now up, will try to setup proxy configuration..."

	[ -d "$conf_dir" ] || mkdir --parents "$conf_dir"
	
	if type -P nmcli &>/dev/null
	then
		# retrieve connection/vpn name
		networkID=`nmcli -t -f name,devices,vpn con status | \
			awk -F':' "BEGIN { device=\"$1\"; event=\"$2\" } \
				event == \"up\" && \\$2 == device && \\$3 == \"no\" { print \\$1 } \
				event == \"vpn-up\" && \\$3 == \"yes\" { print \"vpn_\" \\$1 }"`
	else
		# try ESSID if nmcli is not installed
		logger -p user.notice -t $log_tag "nmcli not detected, will use essid"

		networkID=`iwgetid --scheme`
		[ $? -ne 0 ] && networkID='default'
	fi
	
	# we did not get solve network name
	[ -z "$networkID" ] && networkID='default'
	
	# strip out anything hostile to the file system
	networkID=`echo "$networkID" | tr -c '[:alnum:]-' '_' | sed 's/.$/\n/'`

	conf="$conf_dir/$networkID.conf"

	logger -p user.notice -t $log_tag "using configuration file '$conf'"

	if [ ! -e "$conf" ]
	then
		logger -p user.notice -t $log_tag "configuration file empty! generating skeleton..."

		touch "$conf"

		cat <<EOF > "$conf"
# configuration file for proxydriver
# file auto-generated, please complete me!

# proxy active or not
enabled='false'

# proxy configuration is given by HTTP proxy auto-config (PAC)
# if used, remove comment char '#' at begin of the line
# autoconfig_url=''

# main proxy settings
# if not HTTP proxy auto-config
proxy='proxy.domain.com'
port=8080

# use same proxy for all protocols
same='true'

# protocols other than http
# if not proxy auto-config and if same is set to 'false'
https_proxy='proxy.domain.com'
https_port=8080
ftp_proxy='proxy.domain.com'
ftp_port=8080
socks_proxy='proxy.domain.com'
socks_port=8080

# authentication for Gnome
# for KDE, it is detected automaticaly
auth='false'
login='admin'
pass='pass'

# ignore-list
ignorelist='localhost,127.0.0.0/8,10.0.0.0/8,192.168.0.0/16,172.16.0.0/12'

EOF

		chown root:dip "$conf"
		chmod 0664 "$conf"

	fi

	# read configfile
	source "$conf"

	# select mode using enabled value
	if [ "$enabled" == 'true' -o "$enabled" == '1' -o "$enabled" == 'yes' ]
	then
		enabled='true'              # gnome enable
		kde_mode='1'                # kde fixed proxy
		if [ -n "$autoconfig_url" ]
		then
			gnome_mode='auto'   # gnome autoconfig
			kde_mode='2'        # kde autoconfig
		else
			gnome_mode='manual' # gnome manual
		fi
	else
		enabled='false'
		kde_mode='0'                # kde disabled
		gnome_mode='none'           # gnome disabled
	fi
	#kde_mode> 0: No proxy - 1: Manual - 2: Config url - 3: Automatic (DHCP?) - 4: Use env variables
	#gnome_mode> 'none': No proxy - 'manual': Manual - 'auto': Config url

	if [ "$same" == 'true' -o "$same" == '1' -o "$same" == 'yes' -o -z "$same" ]
	then
		same='true'
		https_proxy="$proxy"
		https_port="$port"
		ftp_proxy="$proxy"
		ftp_port="$port"
		socks_proxy="$proxy"
		socks_port="$port"
	fi

	if [ "$auth" == 'true' -o "$auth" == '1' -o "$auth" == 'yes' ]
	then	
		auth='true'
		shell_auth="$login:$pass@"
	else
		auth='false'
		login=''
		pass=''
		shell_auth=''
	fi

	ignorelist=`echo $ignorelist | sed 's/^\[\(.*\)\]$/\1/'`
	
	# gnome2 needs [localhost,127.0.0.0/8]
	# gnome3 needs ['localhost','127.0.0.0/8']
	# neither works with the other's settings
	quoted_ignorelist=`echo $ignorelist | sed "s/[^,]\+/'\0'/g"`
	gnome2_ignorelist="[${ignorelist}]"
	gnome3_ignorelist="[${quoted_ignorelist}]"
	
	# Gnome likes *.example.com; kde likes .example.com:
	kde_ignorelist=`echo "${ignorelist}" | sed -e 's/\*\./\./g'`
	
	# wait if no users are logged in (up to 5 minutes)
	connect_timer=0
	while [ -z "$(users)" -a $connect_timer -lt 300 ]
	do
		let connect_timer=connect_timer+10
		sleep 10
	done
	
	# a user just logged in; give some time to settle things down
	if [ $connect_timer -gt 0 -a $connect_timer -lt 300 ]
	then
		sleep 15
	fi

	machineid=$(dbus-uuidgen --get)
	for user in `users | tr ' ' '\n' | sort --unique`
	do
		logger -p user.notice -t $log_tag "setting configuration for '$user'"

		cat <<EOS | su -l "$user"
export \$(DISPLAY=':0.0' dbus-launch --autolaunch="$machineid")

# active or not
gconftool-2 --type bool --set /system/http_proxy/use_http_proxy "$enabled"
gsettings set org.gnome.system.proxy.http enabled "$enabled"
gconftool-2 --type string --set /system/proxy/mode "$gnome_mode"
gsettings set org.gnome.system.proxy mode "$gnome_mode"
kwriteconfig --file kioslaverc --group 'Proxy Settings' --key ProxyType "${kde_mode}"

# proxy settings
gconftool-2 --type string --set /system/http_proxy/host "$proxy"
gsettings set org.gnome.system.proxy.http host '"$proxy"'
gconftool-2 --type int --set /system/http_proxy/port "$port"
gsettings set org.gnome.system.proxy.http port "$port"
kwriteconfig --file kioslaverc --group 'Proxy Settings' --key httpProxy "http://${proxy}:${port}/"

gconftool-2 --type bool --set /system/http_proxy/use_same_proxy "$same"
gsettings set org.gnome.system.proxy use-same-proxy "$same"
# KDE handles 'same' in the GUI configuration, not the backend.

gconftool-2 --type string --set /system/proxy/secure_host "$https_proxy"
gsettings set org.gnome.system.proxy.https host '"$https_proxy"'
gconftool-2 --type int --set /system/proxy/secure_port "$https_port"
gsettings set org.gnome.system.proxy.https port "$https_port"
kwriteconfig --file kioslaverc --group 'Proxy Settings' --key httpsProxy "http://${https_proxy}:${https_port}/"

gconftool-2 --type string --set /system/proxy/ftp_host "$ftp_proxy"
gsettings set org.gnome.system.proxy.ftp host '"$ftp_proxy"'
gconftool-2 --type int --set /system/proxy/ftp_port "$ftp_port"
gsettings set org.gnome.system.proxy.ftp port "$ftp_port"
kwriteconfig --file kioslaverc --group 'Proxy Settings' --key ftpProxy "ftp://${ftp_proxy}:${ftp_port}/"

gconftool-2 --type string --set /system/proxy/socks_host "$socks_proxy"
gsettings set org.gnome.system.proxy.socks host '"$socks_proxy"'
gconftool-2 --type int --set /system/proxy/socks_port "$socks_port"
gsettings set org.gnome.system.proxy.socks port "$socks_port"
kwriteconfig --file kioslaverc --group 'Proxy Settings' --key socksProxy "http://${socks_proxy}:${socks_port}/"

# authentication
gconftool-2 --type bool --set /system/http_proxy/use_authentication "$auth"
gsettings set org.gnome.system.proxy.http use-authentication "$auth"
gconftool-2 --type string --set /system/http_proxy/authentication_user "$login"
gsettings set org.gnome.system.proxy.http authentication-user "$login"
gconftool-2 --type string --set /system/http_proxy/authentication_password "$pass"
gsettings set org.gnome.system.proxy.http authentication-password "$pass"
# KDE Prompts 'as needed'
kwriteconfig --file kioslaverc --group 'Proxy Settings' --key Authmode 0

# ignore-list
gconftool-2 --type list --list-type string --set /system/http_proxy/ignore_hosts "${gnome2_ignorelist}"
gsettings set org.gnome.system.proxy ignore-hosts "${gnome3_ignorelist}"
kwriteconfig --file kioslaverc --group 'Proxy Settings' --key NoProxyFor "${kde_ignorelist}"

# gconftool-2 --type string --set /system/proxy/autoconfig_url "${autoconfig_url}"
# gsettings set org.gnome.system.proxy autoconfig-url "${autoconfig_url}"
kwriteconfig --file kioslaverc --group 'Proxy Settings' --key 'Proxy Config Script' "${autoconfig_url}"

# When you modify kioslaverc, you need to tell KIO.
dbus-send --type=signal /KIO/Scheduler org.kde.KIO.Scheduler.reparseSlaveConfiguration string:''
EOS
	done

	# setup shell variables
	# this script should be called from /etc/bash.bashrc
	logger -p user.notice -t $log_tag "building configuration script for shell"

	[ -d `dirname "$proxy_env"` ] || mkdir --parents `dirname "$proxy_env"`
	echo "# shell proxy configuration script for '$networkID'" > "$proxy_env"

	# delete current values
	echo 'unset http_proxy HTTP_PROXY https_proxy HTTPS_PROXY ftp_proxy FTP_PROXY all_proxy ALL_PROXY no_proxy NO_PROXY' >> "$proxy_env"

	if [ "$enabled" == 'true' -a -z "$autoconfig_url" ]
	then
		echo "export http_proxy='http://${shell_auth}${proxy}:${port}/'" >> "$proxy_env"
		echo "export HTTP_PROXY='http://${shell_auth}${proxy}:${port}/'" >> "$proxy_env"
		echo "export https_proxy='http://${shell_auth}${https_proxy}:${https_port}/'" >> "$proxy_env"
		echo "export HTTPS_PROXY='http://${shell_auth}${https_proxy}:${https_port}/'" >> "$proxy_env"
		echo "export ftp_proxy='http://${shell_auth}${ftp_proxy}:${ftp_port}/'" >> "$proxy_env"
		echo "export FTP_PROXY='http://${shell_auth}${ftp_proxy}:${ftp_port}/'" >> "$proxy_env"
		echo "export all_proxy='socks://${shell_auth}${socks_proxy}:${socks_port}/'" >> "$proxy_env"
		echo "export ALL_PROXY='socks://${shell_auth}${socks_proxy}:${socks_port}/'" >> "$proxy_env"
	 	echo "export no_proxy='${ignorelist}'" >> "$proxy_env"
	 	echo "export NO_PROXY='${ignorelist}'" >> "$proxy_env"

	fi

	logger -p user.notice -t $log_tag "configuration done."
fi

