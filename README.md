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

TL;DR: An asynchronous pipe is set up between the Jamf binary and the script. We literally read out and parse the entire verbose output of the Jamf binary to do this. Async because other methods make the binary stall and quit. This method because the information we require does not exist in any other place aka Jamf Log, standard output etc. We also auto generate icon file names from the policy names.

## How do I use this?

- Create a package in your packaging tool of choice.
- Customise the pre and post install scripts to your needs.
- Customise the launch daemon file with your corp details and file locations.
- Customise the main script (see section below) to your needs.
- Add your corporate banner file to the package. (635 × 133 pixel png file is best)
- Add ALL the icon files you're going to require. (We autogenerate the names for those from the policy names.)
- Package, codesign and add to your Jamf Pro prestage.
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

- L20: Log file location.
- L21: Path to working folder. Change this to suit your own needs.
- L22: Name and path of icons folder. Used for banner and auto populating icons.
- L23: Change this to the name and path of your banner image
- L28: Hardcoded URL for Jamf Pro because device wont have enrolled at this stage
- L30: URL of your Jamf Pro server. This runs before any auto detection is possible.
- L31: Your corporate domain. Used for working out email address from current user.
- L468: Regex for automated device naming checks. Currently set to a dummy of 8 numbers only.
