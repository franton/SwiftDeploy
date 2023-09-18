#!/bin/zsh

# Preinstallation script for installing swiftDialog plus deploy
# Very much based on the work of Dan Snelson and Bart Reardon
# Author - richard@richard-purves.com

# Version 1.0 - 04-14-2023

# Variables here
dialogteamid="PWA5E9TQ59"

# We're deploying some branding graphics so let's make sure the folders exist for them to go into!
[ ! -d "/usr/local/corp" ] && mkdir /usr/local/corp

# Now let's make sure the ownership and permissions are correct
chown -R root:wheel /usr/local/corp
chmod -R 755 /usr/local/corp

# Download swiftDialog for our use if it's not already present
if [ ! -e "/Library/Application Support/Dialog/Dialog.app" ];
then
	for i in {1..5};
	do
		echo "Finding swiftDialog latest URL. Attempt $i of 5."
		sdurl=$( /usr/bin/curl -s "https://api.github.com/repos/swiftDialog/swiftDialog/releases/latest" | /usr/bin/awk -F '"' "/browser_download_url/ && /pkg\"/ { print \$4; exit }" )
		[[ "$sdurl" =~ ^https?:\/\/(.*) ]] && break
		sleep 0.2
	done

	# In case things move or the autodetect fails, you can just hardcode a path to the installer here
	#sdurl="https://github.com/bartreardon/swiftDialog/releases/download/v2.2/dialog-2.2.0-4535.pkg"

	[ "$i" -ge 5 ] && { echo "URL detection failed."; exit 1; }

	for i in {1..5};
	do
		echo "Download attempt no. $i of 5."
		httpstatus=$( /usr/bin/curl -L -s -o "/private/tmp/dialog.pkg" "$sdurl" -w "%{http_code}" )
		[ "$httpstatus" = "200" ] && break
		sleep 0.2
	done

	[ "$i" -ge 5 ] && { echo "Download failed."; exit 1; }	
	
	echo "Checking swiftDialog download."
	testteamid=$( /usr/sbin/spctl -a -vv -t install "/private/tmp/Dialog.pkg" 2>&1 | /usr/bin/awk '/origin=/ {print $NF }' | tr -d '()' )
	
	[ "$testteamid" != "$dialogteamid" ] && { echo "Download check failed."; exit 1; }
	
	echo "Installing SwiftDialog."
	/usr/sbin/installer -pkg "/private/tmp/dialog.pkg" -target /
	sleep 2
	
	echo "Checking installed swiftDialog."
	if [ -f "/usr/local/bin/dialog" ];
	then
		echo "swiftDialog version $( /usr/local/bin/dialog --version ) installed."
	else
		echo "swiftDialog install failed."
		exit 1
	fi

else
	echo "SwiftDialog already installed. Skipping download."
fi

/bin/rm -f /private/tmp/dialog.pkg

exit 0
