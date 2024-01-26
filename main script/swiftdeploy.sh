#!/bin/zsh

# Deploy script for SwiftDialog ZeroTouch
# richard@richard-purves.com

# Logging output to a file for testing
#time=$( /bin/date "+%d%m%y-%H%M" )
#set -x
#logfile=/private/tmp/swiftverbose.log
#exec > $logfile 2>&1

# Set up global variables here. User variables to be set up after login.
scriptversion="1.13 - 25th January 2024"

clientid=""
clientsecret=""

ld="/Library/LaunchDaemons/com.jamfsoftware.task.1.plist"
sdld="/Library/LaunchDaemons/com.corp.swiftdeploy.plist"
sdldlabel=$( defaults read $sdld Label )
scriptloc=${0:A}

logfile="/private/tmp/swiftdeploy.log"
workfolder="/usr/local/corp"
icons="$workfolder/deployimgs"
bannerimage="$icons/banner.png"

sdcontrolfile="/private/tmp/sdcontrol.log"

sd="/usr/local/bin/dialog"
jb="/usr/local/bin/jamf"

jssurl="https://corp.jamfcloud.com/"
domain="corp.com"

macosver=$( /usr/bin/sw_vers -productVersion )
majver=$( echo $macosver | cut -d"." -f1 )
macosbuild=$( /usr/bin/sw_vers -buildVersion )
serial=$( /usr/sbin/ioreg -c IOPlatformExpertDevice -d 2 | /usr/bin/awk -F\" '/IOPlatformSerialNumber/{print $(NF-1)}' )
udid=$( /usr/sbin/ioreg -d2 -c IOPlatformExpertDevice | /usr/bin/awk -F\" '/IOPlatformUUID/{print $(NF-1)}' )

# Set up various functions here
function logme()
{
# Check to see if function has been called correctly
	if [ -z "$1" ];
	then
		echo $( /bin/date )" - ERROR: No text passed to function! Please recheck code!" | /usr/bin/tee -a "${logfile}"
		exit 1
	fi

# Log the passed details
	echo -e $( /bin/date )" - $1" | /usr/bin/tee -a "${logfile}"
}

function updatestatus()
{
    logme "SD Command issued: $1"
    echo "$1" >> "$sdcontrolfile"
}

function getjamftoken()
{
	# Check we have the correct number of parameters passed
	if [ $# -lt 3 ];
	then
    	echo "Usage: $funcstack[1] <client id> <client secret> <jss url>"
    	return 1
	fi
	
	# Sort these out into appropriate variables
	id="$1"
	secret="$2"
	jssurl="$3"
	
	# Use the new oauth system to get a bearer token
	jsonresponse=$( /usr/bin/curl --silent --location \
	--request POST "${jssurl}api/oauth/token" \
	--header 'Content-Type: application/x-www-form-urlencoded' \
	--data-urlencode "client_id=${id}" \
	--data-urlencode 'grant_type=client_credentials' \
	--data-urlencode "client_secret=${secret}" )
	
	# Return any replies to the original caller
	echo "$jsonresponse"
}

function invalidatejamftoken()
{
	if [ $# -lt 2 ];
	then
    	logme "Usage: $funcstack[1] <current token> <jss url>"
	fi

	creds="$1"
	jssurl="$2"

	# Send API command to invalidate the token
	/usr/bin/curl -s -k "${jssurl}api/v1/auth/invalidate-token" -H "authorization: Bearer ${token}" -X POST
}

function getcomputerid()
{
	if [ $# -lt 3 ];
	then
    	logme "Usage: $funcstack[1] <jamf api token> <jss url> <udid>"
	fi
	
	apitoken="$1"
	jssurl="$2"
	udid="$3"
	
	compjson=$( /usr/bin/curl -s "${jssurl}api/v1/computers-inventory?section=GENERAL&filter=udid%3D%3D%22${udid}%22" -H "authorization: Bearer ${apitoken}" )
	
	compid=$( /usr/bin/plutil -extract results.0.id raw -o - - <<< "$compjson" )

	echo "$compid"
}

function jamfprocess()
{
	logme "Calling jamf policy $1"

	# Create a named pipe to feed output from jamf binary into.
	# Attach it to file descriptor "3" and delete the created file.
	/usr/bin/mkfifo /private/tmp/jamfoutput
	exec 3<>"/private/tmp/jamfoutput"
	/bin/rm /private/tmp/jamfoutput

	# Run the named policy in the background or check-in if not named,
	# and direct the output to the file descriptor.
	if [ $# -eq 1 ];
	then
		$jb policy -event "$1" -verbose >&3 &
		jbpid=$!
	else
		$jb policy -verbose >&3 &
		jbpid=$!
	fi

	counter=0
	progressbar="1"

	while read output;
	do
		# Uncomment this for actual jamf verbose to a file
		#echo "$output" >> /private/tmp/jamfverbose.log
	
		# Parse for policy list output. If we get one, add to the list.
		if [ $( echo $output | grep -c "verbose: Parsing Policy" ) -gt 0 ];
		then
			array+=(${(f)"$( echo $output | /usr/bin/grep "verbose: Parsing Policy" | /usr/bin/awk '{ print substr($0, index($0,$5)) }' | /usr/bin/awk '{NF--; print}' | /usr/bin/sed 's/Enable //g' | /usr/bin/sed 's/Install //g' | /usr/bin/sed 's/Deploy //g' | /usr/bin/sed 's/Configure //g' )"} )
			image="${icons}/$( echo ${array[-1]} | /usr/bin/tr -d " " | /usr/bin/tr '[:upper:]' '[:lower:]' ).png"
			updatestatus "listitem: add, title: ${array[-1]}, icon: $image, statustext: Waiting, status: pending"
			progressbarstep=$(( 100 / $#array ))
			continue
		fi

		# Work out what policy we're doing and it's status.
		execpolicyname=$( echo $output | grep "Executing Policy" | awk '{ print substr($0, index($1,$5)) }' 2>/dev/null )

		# Save the name for the next loop round. Also work out the proper name for the dialog updates.
		# Also increment the policy counter at the detection of a new policy start.
		if [ ! -z "$execpolicyname" ];
		then
			policyname="$execpolicyname"
			updatename=$( echo $output | awk '{ print substr($0, index($0,$4)) }' )
			updatename=$( echo $updatename | /usr/bin/sed 's/Enable //g' | /usr/bin/sed 's/Install //g' | /usr/bin/sed 's/Deploy //g' | /usr/bin/sed 's/Configure //g' )
		fi

		# If we get a blank line, skip checking for anything.
		# Otherwise parse the verbose output for which state we're in.
		if [ ! -z "$policyname" ];
		then
			downloading=$( echo $output | grep -c "Downloading" )
			installing=$( echo $output | grep -c "Installing" )			# pkgs
			executing=$( echo $output | grep -c "Running script" )		# scripts
			runcommand=$( echo $output | grep -c "Running command" )		# commands
			finished=$( echo $output | grep -c -E 'Successfully|Script exit code: 0|Result of command' )
			failedpkg=$( echo $output | grep -c "Installation failed" )
			failedinstall=$( echo $output | grep "installer:" | grep -c "failed" )
			failedscript=$( echo $output | grep "Script exit code:" | awk '{ print $NF }' )
		fi

		# Depending on state, update swiftDialog list entry
		if [ "$downloading" -eq 1 ];
		then
			updatestatus "listitem: title: $updatename, statustext: Downloading, status: wait"
			updatestatus "progresstext: Downloading $updatename"
		fi

		if [ "$installing" -eq 1 ];
		then
			updatestatus "listitem: title: $updatename, statustext: Installing, status: wait"
			updatestatus "progresstext: Installing $updatename"
		fi

		if [ "$executing" -eq 1 ];
		then
			updatestatus "listitem: title: $updatename, statustext: Running Script, status: wait"
			updatestatus "progresstext: Running Script for $updatename"	
		fi

		if [ "$runcommand" -eq 1 ];
		then
			updatestatus "listitem: title: $updatename, statustext: Running Command, status: wait"
			updatestatus "progresstext: Running Command for $updatename"		
		fi

		if [ "$failedpkg" -eq 1 ] || [ "$failedinstall" -eq 1 ] || [ "$failedscript" -ne 0 ];
		then
			progressbar=$(( $progressbar + $progressbarstep ))
			counter=$(( $counter + 1 ))
			updatestatus "progress: $progressbar"
			updatestatus "listitem: title: $updatename, statustext: Failed, status: fail"
			updatestatus "progresstext: Installatiion of $updatename FAILED"
			unset execpolicyname policyname
		fi

		if [ "$finished" = "1" ];
		then
			progressbar=$(( $progressbar + $progressbarstep ))
			counter=$(( $counter + 1 ))
			updatestatus "progress: $progressbar"
			updatestatus "listitem: title: $updatename, statustext: Completed, status: success"
			updatestatus "progresstext: $updatename Completed"
		
			# Clean out previous completed task. Only ones left should be the failed ones.
			# Then store the current name to be cleaned on the next task
			[ ! -z "$previouspolicy" ] && updatestatus "listitem: delete, title: $previouspolicy"
			previouspolicy="$updatename"

			unset execpolicyname policyname
		fi

		# Clear variables for future loops
		unset downloading installing executing finished	failedpkg failedscript
	
		# Loop will never exit on it's own. Break out when the counter
		# reaches the same or greater number than the indexes in the deployarray array.
		[ "$counter" -ge "$#array" ] && [ "$#array" -gt 0 ] && break
	
	done <&3

	# Clear the file descriptor we set up earlier
	exec 3>&-

	# Ensure the Jamf Binary has terminated before proceeding
	wait $jbpid

	# Clear final icon from the list
	updatestatus "listitem: delete, title: $previouspolicy"

	# Clear remaining variables used
	unset previouspolicy array counter jbpid
}

function exitscript()
{
	if [ $# -lt 2 ]
	then
    	logme "Usage: $funcstack[1] <exit code> <message>"
    	exit 1
	fi

	logme "Exit code: $1"
	logme "Exit message: $2"

	/bin/rm -rf "$icons"
	/bin/rm -f "$sdcontrolfile"
	/bin/rm -f "$sdld"
	/bin/rm "$scriptloc"
	/bin/launchctl bootout system/$sdldlabel
	sleep 1
	
	# parse $1 to get exit code.
	exit $1
}

#
## Start preparation for deployment
#

# Set error trapping here
trap 'logme "Error at line $LINENO"; exitscript 1 "Script error. Check /private/tmp/swiftdeploy.log"'

# Caffeinate the mac so it doesn't go to sleep on us. Give it the PID of this script
# so that it auto quits when we're done.
logme "Starting Deployment preparation."
logme "Loading caffeinate so the computer doesn't sleep."
/usr/bin/caffeinate -dimu -w $$ &

# Loop and wait for enrollment to complete
while [ -f /Library/LaunchDaemons/com.jamf.management.enroll.plist ]; do : ; done

# Ensure checkin is disabled
while [ ! -f "$ld" ]; do : ; done
/bin/launchctl bootout system "$ld"

# Enable localadmin SSH access
logme "Enabling SSH access for admin account."
/usr/sbin/systemsetup -f -setremotelogin off 2>&1 >/dev/null
/usr/sbin/dseditgroup -o delete -t group com.apple.access_ssh 2>&1 >/dev/null
/usr/sbin/dseditgroup -o create -q com.apple.access_ssh 2>&1 >/dev/null
/usr/sbin/dseditgroup -o edit -a admin -t user com.apple.access_ssh 2>&1 >/dev/null
/usr/sbin/systemsetup -f -setremotelogin on 2>&1 >/dev/null

# Wait for the user environment to start before we proceed. Also make sure Jamf check in is disabled.
logme "Waiting for user login before proceeding."
while ! /usr/bin/pgrep -xq Finder;
do
	if [ $( /bin/launchctl list | /usr/bin/grep -c "com.jamfsoftware.task.Every 15 Minutes" ) != "0" ];
	then
		logme "Disabling Jamf Check-In."
		/bin/launchctl bootout "system/com.jamfsoftware.task.Every 15 Minutes"
		jamfpid=$( /bin/ps -ax | /usr/bin/grep "jamf policy -randomDelaySeconds" | /usr/bin/grep -v "grep" | /usr/bin/awk '{ print $1 }' )
		[ "$jamfpid" != "" ] && kill -9 "$jamfpid"
		unset jamfpid
	fi
done
logme "Dock process running. Starting deployment process."

# Attempt to check if device has properly enrolled into Jamf Pro
logme "Checking if Jamf Enrollment has completed properly"
jsstest=$( /usr/local/bin/jamf policy -event isjssup 2>/dev/null | /usr/bin/grep -c "Script result: up" )

# Initiate re-enrollment of computer if the earlier test failed
if [ "$jsstest" = "0" ];
then
	# Write marker file for Jamf auditing
	/usr/bin/touch ${workfolder}/enrollretry

	# Jamf API enrollment credentials and URL	
	jsonresponse=$( getjamftoken "$clientid" "$clientsecret" "$jssurl" )

	jamftoken=$( /usr/bin/plutil -extract access_token raw -o - - <<< "$jsonresponse" )
	type=$( /usr/bin/plutil -extract token_type raw -o - - <<< "$jsonresponse" )
	expiry=$( /usr/bin/plutil -extract expires_in raw -o - - <<< "$jsonresponse" )

	# Find and grab computer jamf ID number
	jamfid=$( getcomputerid "$jamftoken" "$jssurl" "$udid" )

	# Send re-enrollment command
	/usr/bin/curl -s -X POST "${jssurl}api/v1/jamf-management-framework/redeploy/${jamfid}" -H "accept: application/json" -H "Authorization: ${type} ${jamftoken}"

	# Invalidate the requested API token
	invalidatejamftoken "$token" "$jssurl"

	# No computer record, thus we can't re-enroll so we must exit hard here.
	if [[ "$computerid" =~ stdin ]];
	then
		opts+=(${(f)}"--title \"Computer Deployment Failed\"")
		opts+=(${(f)}"--icon ${icons}/jamfuserdetails.png")
		opts+=(${(f)}"--message \"Your computer has failed to install correct software. \n\nClick [here to contact IT Support](https://help.corp.com) and request assistance. \n\nThen please click \"Finish\" to exit this message.\n\nThis message will automatically disappear in 30 seconds time.\"")
		opts+=(${(f)}"--quitkey o")
		opts+=(${(f)}"--position center")
		opts+=(${(f)}"--timer 30")
		opts+=(${(f)}"--button1text \"Finish\"")

		eval "$sd" --args "${opts[*]}" &
		sleep 0.1

		exitscript 1 'Re-enrollment of device failed'
	fi

	# Wait for enrollment to complete
	while [ "$jsstest" != "0" ]; do jsstest=$( /usr/local/bin/jamf policy -event isjssup 2>/dev/null | /usr/bin/grep -c "Script result: up" ); sleep 0.1; done
fi

# Kill any check-in in progress
jamfpid=$( /bin/ps -ax | /usr/bin/grep "jamf policy -randomDelaySeconds" | /usr/bin/grep -v "grep" | /usr/bin/awk '{ print $1 }' )
if [ "$jamfpid" != "" ];
then
	kill -9 "$jamfpid"
fi

#
## Start the deployment process now a user has logged in 
#

# Write out deployment start timestamp
timestamp=$( /bin/date '+%Y-%m-%d %H:%M:%S' | /usr/bin/tee -a $workfolder/.deploystart )

# Who's the current user and their details?
currentuser=$( /usr/sbin/scutil <<< "show State:/Users/ConsoleUser" | /usr/bin/awk -F': ' '/[[:space:]]+Name[[:space:]]:/ { if ( $2 != "loginwindow" ) { print $2 }}' )
userid=$( /usr/bin/id -u $currentuser )
userhome=$( /usr/bin/dscl . read /Users/${currentuser} NFSHomeDirectory | /usr/bin/awk '{print $NF}' )
userpref="${userhome}/Library/Preferences/com.jamf.connect.state.plist"
useremail="${currentuser}@${domain}"
userkeychain="${userhome}/Library/Keychains/login.keychain-db"
jssurl=$( /usr/bin/defaults read /Library/Preferences/com.jamfsoftware.jamf.plist jss_url )

# Work out user's first name and capitalise first letter
firstname=$( echo $currentuser | /usr/bin/cut -d"." -f1 )
firstname=$( /usr/bin/tr '[:lower:]' '[:upper:]' <<< ${firstname:0:1} )${firstname:1}

#
## Load the initial swiftDialog screen
#
logme "Start the swiftDialog process with the initial screen."

# Set initial icon based on whether the Mac is a desktop or laptop
# Use SF symbols for this https://developer.apple.com/sf-symbols/
if /usr/sbin/ioreg -rd1 -c IOPlatformExpertDevice | /usr/bin/awk -F'["|"]' '/model/{print $4}' | /usr/bin/grep -q "Book";
then
	icon="SF=laptopcomputer.and.arrow.down,weight=semibold,colour1=black"
else
	icon="SF=desktopcomputer.and.arrow.down,weight=semibold,colour1=black"
fi

dialogver=$( /usr/local/bin/dialog --version )

title="Hi $firstname, Welcome to your new computer!"
message="Please wait while we configure your computer ..."
helpmessage="If you need assistance, please contact the IT Service Desk:  \n- e-mail your line manager.  \n\n**Computer Information:**  \n- **Operating System:**  ${macosver} (${macosbuild})  \n- **Serial Number:** ${serial}  \n- **Dialog:** ${dialogver}  \n- **Started:** ${timestamp}"
infobox="TRR Device Info\n\n**Username:**\n- Pending\n\n**Computer Name:**  \n- Pending\n\n**Department**\n- Pending\n\n**Location**\n- Pending"

# Set an array of options here. (If you're wondering what all this ${(f)}) stuff is,
# it's a better way of not splitting on spaces without messing with IFS.
opts+=(${(f)}"--bannerimage \"$bannerimage\"")
opts+=(${(f)}"--title \"$title\"")
opts+=(${(f)}"--message \"$message\"")
opts+=(${(f)}"--helpmessage \"$helpmessage\"")
opts+=(${(f)}"--icon \"$icon\"")
opts+=(${(f)}"--infobox \"${infobox}\"")
opts+=(${(f)}"--progress")
opts+=(${(f)}"--progresstext \"Initializing configuration ...\"")
opts+=(${(f)}"--button1text \"Wait\"")
opts+=(${(f)}"--button1disabled")
opts+=(${(f)}"--infotext \"$scriptversion\"")
opts+=(${(f)}"--messagefont 'size=14'")
opts+=(${(f)}"--height '780'")
opts+=(${(f)}"--position centre")
opts+=(${(f)}"--blurscreen")
opts+=(${(f)}"--ontop")
opts+=(${(f)}"--quitkey o")
opts+=(${(f)}"--commandfile \"$sdcontrolfile\"")

# Now run swiftDialog and get this party started
eval "$sd" "${opts[*]}" &

# Wait and clear the options array
sleep 1
unset opts

#
## Get current user details and put them in Jamf but also ...
#

# Set up the first two list items by hand
updatestatus "list: show"
sleep 1
updatestatus "listitem: add, title: Update Jamf User Details, icon: ${icons}/jamfuserdetails.png, statustext: Waiting, status pending"
updatestatus "listitem: add, title: Set Computer Name, icon: ${icons}/setcomputername.png, statustext: Waiting, status: pending"

## HORRIBLE workaround for Jamf Connect bug
logme "Writing username: $useremail to Jamf Connect plist"
updatestatus "progresstext: Update Jamf User Details"
updatestatus "listitem: title: Update Jamf User Details, statustext: Configuring, status: wait"
/bin/launchctl bootout gui/$userid /Library/LaunchAgents/com.jamf.connect.plist
/usr/bin/defaults write "$userpref" DisplayName -string "$useremail"
/usr/sbin/chown ${currentuser}:staff "$userpref"
/usr/local/bin/jamf policy -event getusername
updatestatus 'infobox: Device Info\\n\\n**Username:** \\n- '"$currentuser"'\\n\\n**Computer Name:** \\n- Pending\\n\\n**Department**\\n- Pending\\n\\n**Location**\\n- Pending'
updatestatus "listitem: title: Update Jamf User Details, statustext: Completed, status: success"

#
## Set computer name via auto script in Jamf.
#
logme "Setting computer name via Jamf policy"
updatestatus "listitem: title: Set Computer Name, statustext: Configuring, status: wait"
updatestatus "progresstext: Setting Computer Name"
/usr/local/bin/jamf policy -event autoname
computername=$( /usr/sbin/scutil --get ComputerName )

# Now the computer hostname. Do a regex match for 12345678 type format.
logme "Checking if computer name was set correctly"
if [[ $computername =~ ^[0-9]{8}$ ]];
then
	logme "Computer name is in the correct format"
	updatestatus "listitem: title: Set Computer Name, statustext: Completed, status: success"
else
	logme "Computer name not set correctly"
	computername="ERROR"
	updatestatus "listitem: title: Set Computer Name, statustext: Failed, status: fail"
fi
updatestatus 'infobox: Device Info\\n\\n**Username:** \\n- '"$currentuser"'\\n\\n**Computer Name:** \\n- '"$computername"'\\n\\n**Department**\\n- Pending\\n\\n**Location**\\n- Pending'

#
## Get building and department info
#

# Obtain an access token for the Jamf API
jsonresponse=$( getjamftoken "$clientid" "$clientsecret" "$jssurl" )
jamftoken=$( /usr/bin/plutil -extract access_token raw -o - - <<< "$jsonresponse" )
type=$( /usr/bin/plutil -extract token_type raw -o - - <<< "$jsonresponse" )

# Now get the device record from the hardware udid
deviceuserrecord=$( /usr/bin/curl -s -X GET "${jssurl}api/v1/computers-inventory/?section=USER_AND_LOCATION&page=0&page-size=1&sort=id%3Aasc&filter=udid%3D%3D${udid}" -H "accept: application/json" -H "authorization: ${type} ${jamftoken}" )

# From that we can extract out the building and department info from the device record
buildingid=$( /usr/bin/plutil -extract results.0.userAndLocation.buildingId raw -o - - <<< "$deviceuserrecord" )
departmentid=$( /usr/bin/plutil -extract results.0.userAndLocation.departmentId raw -o - - <<< "$deviceuserrecord" )

# Problem: They're listed in the record as their Jamf ID numbers. So do more calls to capture the records for those IDs
buildingjson=$( /usr/bin/curl -s -X GET "${jssurl}api/v1/buildings/${buildingid}" -H "accept: application/json" -H "authorization: Bearer ${jamftoken}" )
departmentjson=$( /usr/bin/curl -s -X GET "${jssurl}api/v1/departments/${departmentid}" -H "accept: application/json" -H "authorization: Bearer ${jamftoken}" )

building=$( /usr/bin/plutil -extract name raw -o - - <<< "$buildingjson" 2>/dev/null )
department=$( /usr/bin/plutil -extract name raw -o - - <<< "$departmentjson" 2>/dev/null )

# Finally we have names. Or do we? Fail out if not. Report if we do.
if [ ! -z "$building" ] && [ ! -z "$department" ];
then
	updatestatus 'infobox: Device Info\\n\\n**Username:** \\n- '"$currentuser"'\\n\\n**Computer Name:** \\n- '"$computername"'\\n\\n**Department**\\n- '"$department"'\\n\\n**Location**\\n- '"$building"''
else
	updatestatus 'infobox: Device Info\\n\\n**Username:** \\n- '"$currentuser"'\\n\\n**Computer Name:** \\n- '"$computername"'\\n\\n**Department**\\n- Retrieval FAILED\\n\\n**Location**\\n- Contact I.T.'
fi

# Invalidate the requested API token
invalidatejamftoken "$jamftoken" "$jssurl"

# Clean up icons
updatestatus "listitem: delete, title: Update Jamf User Details"
updatestatus "listitem: delete, title: Set Computer Name"

#
## Software Deployment Prep Process
#
logme "Getting policy list from Jamf"
updatestatus "progresstext: Starting Deployment Process"
jamfprocess deploy

#
## Device Inventory Process
#
updatestatus "listitem: add, title: Update Inventory, icon: ${icons}/updateinventory.png, statustext: In Progress, status: pending"
updatestatus "progresstext: Updating Jamf Inventory Record"
$jb recon
updatestatus "listitem: title: Update Inventory, statustext: Completed, status: success"
sleep 1

#
## Check-in Policy Process
#
updatestatus "progresstext: Starting check-in policies"
updatestatus "listitem: delete, title: Update Inventory"
jamfprocess

#
## Set up following tasks to be displayed
#
updatestatus "listitem: add, title: Enable Jamf Check-In, icon: ${icons}/jamfcheckin.png, statustext: Waiting, status: pending"
updatestatus "listitem: add, title: Finalising Deployment, icon: ${icons}/finished.png, statustext: Waiting, status: pending"
sleep 1

#
## Re-enable Jamf check-in
#
updatestatus "progresstext: Enabling Jamf Check-In"
updatestatus "listitem: title: Enable Jamf Check-In, statustext: Waiting, status: wait"
/bin/launchctl bootstrap system "$ld"
sleep 1
updatestatus "listitem: title: Enable Jamf Check-In, statustext: Completed, status: success"

#
## Create deploy finished touch file and final device inventory process
#
updatestatus "listitem: title: Finalising Deployment, statustext: Waiting, status: pending"
updatestatus "progresstext: Finalising the device deployment"
/bin/date '+%Y-%m-%d %H:%M:%S' | /usr/bin/tee -a $workfolder/.deploycomplete
$jb recon

#
## Force Jamf Connect menu agent to run
#
/bin/launchctl bootstrap gui/$userid /Library/LaunchAgents/com.jamf.connect.plist
sleep 1
updatestatus "listitem: delete, title: Enable Jamf Check-In"
updatestatus "listitem: title: Finalising Deployment, statustext: Completed, status: success"

#
## Quit main swiftDialog window
#
updatestatus "progresstext: Deployment Completed"
sleep 10
updatestatus "quit:"
sleep 0.1

#
## Clean up files and script and exit
#
logme "Cleaning up working files and exiting."
exitscript 0 'Success!'
