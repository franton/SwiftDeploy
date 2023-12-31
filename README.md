# SwiftDeploy
Zero touch deployment method for Jamf Pro and SwiftDialog

This project is directly inspired by [Setup Your Mac](https://snelson.us/sym) by Dan Snelson, is meant for exclusive use with [Jamf Pro](https://www.jamf.com/products/jamf-pro/) management system and finally makes extensive use of [SwiftDialog](https://github.com/swiftDialog/swiftDialog) by Bart Reardon.

To those projects and authors, I give my thanks.

## What does this do?

I like [Setup Your Mac](https://snelson.us/sym) as a concept, but unfortunately I have requirements for a more complex and flexible system. As a result, SwiftDeploy now exists.

The principle difference between the two projects is that I worked out a way to autogenerate the policy lists in SwiftDialog directly from the output of the Jamf binary instead of hard coding everything. So at the expense of code complexity, this system will auto generate and display the correct list every time.

## Can I see this in action?

Sure!

https://github.com/franton/SwiftDeploy/assets/5807892/f8382ff2-e7f8-43b4-9d73-0e767a8cfe5f

This shows a very sped up deployment process, where the script initiated the following process:

- Work out the name of the user that signed in and upload that to Jamf Pro.
- Auto set the name of the computer based on the asset management system data.
- Execute a ```jamf policy -event deploy -verbose``` command.
- Then execute a ```jamf policy -verbose``` command to run check in.
- Re-enables Jamf automatic check in.
- Cleans up and exits.

For those who remember my JNUC 2022 talk, I am still claiming the prize for fastest Touch ID setup ever :D

## What sorcery is this?

Blog post coming soon that will go into details.

TL;DR:

A pipe is set up between the Jamf binary and this script, and we force this to operate in an asychronous mode. The risk otherwise is the pipe could stall and the binary could be prematurely terminated. We invoke the binary using the verbose switch to get extra output.

A script loop, coded to be as fast as possible processes the output received from the pipe and updates SwiftDialog accordingly

From all the verbose output we get all the policy names that the binary is to act on. Those names are processed into image files names so we can use appropriately named files. We also get start info, is a policy running a pkg or a script, did it work or did it fail and update accordingly. We also know when we're finished because otherwise async pipes don't terminate.

The blog post will have more detail. [Eventually.](https://developer.valvesoftware.com/wiki/Valve_Time). 

## How do I use this?

- Create a package in your packaging tool of choice.
- Customise the pre and post install scripts to your needs.
- Customise the launch daemon file with your corp details and file locations.
- Customise the main script (see section below) to your needs.
- Add your corporate banner file to the package. (635 × 133 pixel png file is best)
- Add ALL the icon files you're going to require. (We autogenerate the names for those from the policy names.)
- Package, codesign and add to your Jamf Pro prestage.
- Create a policy in Jamf with the custom trigger "isjssup", Ongoing that simply runs ```echo "up"``` .
- TEST!

Here's a screenshot from my packaging project so you can see where all the files are located.

<img width="976" alt="swiftdeploypkg" src="https://github.com/franton/SwiftDeploy/assets/5807892/74ef209a-4fb3-4267-8aea-1339f47ed02e">

## Icon file example.

A policy with a name such as
```Deploy BeyondTrust Support Client```
is translated to
```beyondtrustsupportclient.png```

The code chops off the first word, amalgamates the other text, forces lower case and assumes .png format.

All files I generated using [SAP's macOS icon generator](https://github.com/SAP/macOS-icon-generator) at 512x512 png.

By default ALL icon files live in /usr/local/corp/deployimgs but that can be customised. See section below.

## Areas of note in the code:

- L15 and 16: Jamf API Role client id and secret. Used for various API accesses.

  | Permissions |
  | ------ |
  | Read Buildings |
  | Read Computers |
  | Read Departments |
  | Read Computer Check-In |
  | Send Computer Remote Command to Install Package |

- L20: Log file location.
- L21: Path to working folder. Change this to suit your own needs.
- L22: Name and path of icons folder. Used for banner and auto populating icons.
- L23: Change this to the name and path of your banner image
- L28: Hardcoded URL for Jamf Pro because device wont have enrolled at this stage
- L30: URL of your Jamf Pro server. This runs before any auto detection is possible.
- L31: Your corporate domain. Used for working out email address from current user.
- L319: Detection code to see if enrollment failed and initiate re-enrollment if so. Uses same client id/secret.
- L446: Custom code to run named triggers for adding user details to device record and device naming. (Not provided in this project.)
- L468: Regex for automated device naming checks. Currently set to a dummy of 8 numbers only.

## Acknowledgements

[Mac Admins Slack](https://www.macadmins.org/)
- @dan-snelson For his Setup Your Mac project showing it was all possible
- @bartreardon For his SwiftDialog project that really made the display possible
- @pico For advise on some of the nastier bits of shell pipe handling. (Although neither of us had gone quite this far!)
- The current users of the #zsh , #bash and #swiftdialog channels. (Hi to #jamfnation too!)
- The original authors of cocoaDialog for putting the idea of named async pipes in my head from their original documentation
- @tlark @macmule @rabbitt @bradtchapman @rquigley @marcusransom and other for support and chats during the development of this.

If i've missed you out, get in touch and i'll fix that mistake.
