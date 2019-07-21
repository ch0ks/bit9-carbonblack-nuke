#!/usr/bin/env bash
#title          :Nuke CarbonBlack agent from existance
#description    :This is an old scrip deveploed in 2016. Use at your own risk.
#                This script will remove CarbonBlack agent from any OSX machine before
#                El Capitan. Requires root and it's considered a PoC
#file_nam       :CarbonBlackNuke.sh.sh
#author         :Adrian Puente
#date           :20160315
#version        :1.8
#bash_version   :4.4.19
#==================================================================

# Make sure only root can run our script
if [[ $EUID -ne 0 ]]; then
    echo "The uninstaller must be run as root."
    exit 1
fi

LOG=/var/log/cblog.log

# Tell the user what is happening
echo ""
echo "Beginning uninstall of the Carbon Black Sensor."

echo "STARTING SENSOR UNININSTALL SCRIPT" >> $LOG 2>&1

echo "" >> $LOG 2>&1
curDate=`date`
VER=`/usr/bin/sw_vers -productVersion`

echo "   $curDate" >> $LOG 2>&1
echo "   OS X Version $VER" >> $LOG 2>&1

# Unload the daemon and kernel extensions before removing anything.
echo "" >> $LOG 2>&1
echo "   Stopping The CarbonBlack Daemon..." >> $LOG 2>&1

# Wait for the daemon to stop before proceeding.
cbdpid=$(ps -axf | grep CbOsxSensorService | grep -v grep | grep -v bash | awk '{print $2}')

sudo launchctl unload /Library/LaunchDaemons/com.carbonblack.daemon.plist &> /dev/null

sleep 3

startTime=$(date +%s)

declare -i rebootNecessary
rebootNecessary=0

while ps -p $cbdpid &> /dev/null; do
    sleep 1
    curTime=$(($(date +%s)-startTime))

    ## give up after 5 minutes
    if (test $curTime -gt 300) ; then
        echo "   The daemon did not shutdown properly. Uninstall will remove the files, but a reboot will be necessary." >> $LOG 2>&1
        rebootNecessary=1
    fi
done;

declare -i nokext1
declare -i nokext2
nokext1=0
nokext2=0

# Location of KEXT now depends on platform (pre 10.9 or 10.9 and later)
# we'll attempt to unload both and remove both if both are present.
if (test -d "/System/Library/Extensions/CbOsxSensorProcmon.kext") ; then
    CBPKEXTLOCATION1=/System/Library/Extensions/CbOsxSensorProcmon.kext
    CBNKEXTLOCATION1=/System/Library/Extensions/CbOsxSensorNetmon.kext
fi

if (test -d "/Library/Extensions/CbOsxSensorProcmon.kext") ; then
    CBPKEXTLOCATION2=/Library/Extensions/CbOsxSensorProcmon.kext
    CBNKEXTLOCATION2=/Library/Extensions/CbOsxSensorNetmon.kext
fi

# Only stop the kexts if the daemon could be stopped.
if [[ rebootNecessary -eq 0 ]]; then

    echo "   Daemon stopped." >> $LOG 2>&1
    echo "" >> $LOG 2>&1

    # A function that waits for a kext to unload. If the kext is not loaded,
    # this function will return succesfully immediatly.  If the kext does not
    # unload in 5 minutes, the script will exit with an error status.
    function waitForKext {
        startTime=$(date +%s)

        echo "   Waiting for KEXT $1 to shutdown..."  >> $LOG 2>&1
        while kextstat | grep "$1" &> /dev/null; do
            sleep 1
            curTime=$(($(date +%s)-startTime))

            ## give up after 30 seconds
            if (test $curTime -gt 30) ; then
                echo "   KEXT $1 did not shutdown properly. Installation will not proceed" >> $LOG 2>&1
                exit 1
            fi
        done;

        echo "   KEXT $1 is shutdown." >> $LOG 2>&1
    }

    CBKERNELPROCMONID="com.carbonblack.CbOsxSensorProcmon"
    CBKERNELNETMONID="com.carbonblack.CbOsxSensorNetmon"

    # Make sure there is a kext
    if test -n "$CBPKEXTLOCATION1" ; then
        echo "   KEXT found at $CBPKEXTLOCATION1, unloading..." >> $LOG 2>&1
        sudo kextunload $CBPKEXTLOCATION1 > /dev/null 2>&1
        waitForKext "$CBKERNELPROCMONID"
        sudo kextunload $CBNKEXTLOCATION1 > /dev/null 2>&1
        waitForKext "$CBKERNELNETMONID"
    else
        nokext1=1
    fi

    # Make sure there is a kext
    if test -n "$CBPKEXTLOCATION2" ; then
        echo "   KEXT found at $CBPKEXTLOCATION2, unloading..." >> $LOG 2>&1
        sudo kextunload $CBPKEXTLOCATION2 > /dev/null 2>&1
        waitForKext "$CBKERNELPROCMONID"
        sudo kextunload $CBNKEXTLOCATION2 > /dev/null 2>&1
        waitForKext "$CBKERNELNETMONID"

    else
        nokext2=1
    fi

    # Sanity check to make sure if no KEXT was found on the file system, that it's also not loaded.
    if [[ nokext1 -eq 1 ]] || [[ nokext2 -eq 1 ]] ; then
        kextstat | grep "$CBKERNELPROCMONID" &> /dev/null
        kextRes=$?
        if [[ kextRes -eq 0 ]]; then
            echo "   The CarbonBlack KEXT was not found, but is loaded. A reboot before proceeding is necessary." >> $LOG 2>&1
            rebootNecessary=1
        fi

        kextstat | grep "$CBKERNELNETMONID" &> /dev/null
        kextRes=$?
        if [[ kextRes -eq 0 ]]; then
            echo "   The CarbonBlack KEXT was not found, but is loaded. A reboot before proceeding is necessary." >> $LOG 2>&1
            rebootNecessary=1
        fi

    fi

    echo "" >> $LOG 2>&1
    echo "   Driver stopped." >> $LOG 2>&1

fi

#
# File removal.
#
echo "" >> $LOG 2>&1
echo "   Removing files..." >> $LOG 2>&1
if [[ nokext1 -eq 0 ]] ; then
    rm -rf "$CBPKEXTLOCATION1" >> $LOG 2>&1
    rm -rf "$CBNKEXTLOCATION1" >> $LOG 2>&1
fi

if [[ nokext2 -eq 0 ]] ; then
    rm -rf "$CBPKEXTLOCATION2" >> $LOG 2>&1
    rm -rf "$CBNKEXTLOCATION2" >> $LOG 2>&1
fi

rm -f /Library/LaunchDaemons/com.carbonblack.daemon.plist >> $LOG 2>&1
rm -rf /Applications/CarbonBlack >> $LOG 2>&1

if !(test "$1" = "d") && !(test "$1" == "-d"); then
    echo "   Removing data directory..." >> $LOG 2>&1
    rm -fR "/var/lib/cb"
fi


# Unregister the installed packages
echo "" >> $LOG 2>&1
echo "   Unregistering installation packages..." >> $LOG 2>&1
pkgutil --forget com.carbonblack.CbOsxSensorService.pkg &> /dev/null
pkgutil --forget com.carbonblack.daemon.pkg &> /dev/null
pkgutil --forget com.carbonblack.sensoruninst.pkg &> /dev/null
pkgutil --forget com.carbonblack.sensordiag.pkg &> /dev/null
pkgutil --forget com.carbonblack.Kext.pkg &> /dev/null
pkgutil --forget com.carbonblack.Kext10.pkg &> /dev/null

if [[ rebootNecessary -eq 1 ]]; then
    echo "Carbon Black was uninstalled, but the services could not be stopped."
    echo "You will need to reboot in order to complete the unisntall."
    echo "Reboot Required" >> $LOG 2>&1
fi

# Tell the user what is happening
echo ""
echo "Uninstall of the Carbon Black Sensor is complete."

# Remove the unisntall job if there is one
export CBUNINSTALL=`sudo launchctl list | grep com.carbonblack.Uninstall`
if ( test -n "$CBUNINSTALL" ); then
    launchctl remove com.carbonblack.Uninstall
fi

echo "" >> $LOG 2>&1
echo "EXITING SENSOR UNINSTALL SCRIPT" >> $LOG 2>&1
