#!/bin/zsh

# Preinstallation script for installing swiftDialog plus deploy
# Author - richard@richard-purves.com

# Version 1.0 - 04-14-2023

# Check for current logged in user
loggedinuser=$( /usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }}' )

# For some reason best known to Apple, our files occasionally have quarantine attributes set. Fix this.
/usr/bin/xattr -r -d com.apple.quarantine /usr/local/corp
/usr/bin/xattr -r -d com.apple.quarantine /Library/LaunchDaemons/com.corp.swiftdeploy.plist
/usr/bin/xattr -r -d com.apple.quarantine /Library/Application\ Support/Dialog
/usr/bin/xattr -r -d com.apple.quarantine /usr/local/bin/dialog

# If loginwindow, setup assistant or no user, then we're in a DEP environment. Load the LaunchDaemon.
if [[ "$loggedinuser" = "loginwindow" ]] || [[ "$loggedinuser" = "_mbsetupuser" ]] || [[ -z "$loggedinuser" ]];
then
	/bin/launchctl bootstrap system /Library/LaunchDaemons/com.corp.swiftdeploy.plist
fi

# User initiated enrollment devices excluded. We'll pick them up after a restart via Jamf.
exit