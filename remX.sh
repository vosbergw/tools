#!/bin/bash
# 
# This file is part of remX.
# 
# remX is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# remX is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with remX.  If not, see <http://www.gnu.org/licenses/>.
# 
# Copyright 2013 Wayne Vosberg <wayne.vosberg@mindtunnel.com>

. ~/lib/bash.utils/utils.sh || exit

if [[ ${#1} == 0 ]]
then
  echo "usage: $0 <user>@<remote host>[:port]"
  exit
fi

ME=$BASHPID
REMOTE=$(echo $1 | cut -d: -f1)
PORT=$(echo $1 | cut -d: -f2)
USER=$(echo $REMOTE | cut -d"@" -f1)
GEOMETRY="1024x768"

SSH="/usr/bin/ssh"
if [[ ${#PORT} -gt 0 ]]
then
  SSH="$SSH -p $PORT"
fi

FWD="-fax -L 5902:localhost:5900 -o ExitOnForwardFailure=yes"
FWDX="-fa -L 5902:localhost:5900 -o ExitOnForwardFailure=yes"

RREMX="export UNIXPW_DISABLE_SSL=1; export SUDO_ASKPASS=/usr/bin/ssh-askpass; \
    sudo -A /usr/bin/x11vnc --quiet -nopw -once -timeout 60 -nolookup -solid \
    -localhost -auth $AUTH -users $USER -ncache 10 -xkb \
    -display :0"

UREMX="export UNIXPW_DISABLE_SSL=1 ; /usr/bin/x11vnc --quiet -nopw -once \
    -timeout 60 -nolookup -solid -localhost -ncache 10 -xkb -display :0" 




function kill_x11vnc()
{
  # usage: kill_x11vnc user@remote

  X11PIDS=$($SSH $REMOTE pgrep x11vnc)
  if [[ ${#X11PIDS} -gt 0 ]]
  then
    echo "pkill any straggling x11vnc process on $REMOTE"
    $SSH $REMOTE "kill $X11PIDS" >>/dev/null 2>&1
    # if there are any left, do again as root
    X11PIDS=$($SSH $REMOTE pgrep x11vnc)
    if [[ ${#X11PIDS} -gt 0 ]]
    then
      $SSH -t $REMOTE "export SUDO_ASKPASS=/usr/bin/ssh-askpass ; \
        sudo -A kill $X11PIDS" >>/dev/null 2>&1
    fi
  fi
}


####### main entry point



if [[ ${#VNCVIEWER} -gt 0 ]] 
then
  echo "using \$VNCVIEWER: $VNCVIEWER"
  VIEWER="$VNCVIEWER"
elif [[ -x /usr/bin/ssvncviewer ]]
then
  # -user $USER -unixpw ."
  VIEWER="/usr/bin/ssvncviewer -scale $GEOMETRY -encodings zrle \
    -compresslevel 9 -16bpp localhost::5902"
  echo -e "using: $VIEWER\n\n"
elif [[ -x /usr/bin/xtightvncviewer ]]
then
  VIEWER="/usr/bin/xtightvncviewer -encodings tight -compresslevel 9 \
    -geometry $GEOMETRY localhost::5902"
  echo    "using: $VIEWER"
  echo -e " NOTE: for scaling the remote console use ssvncviewer!\n\n"
elif [[ -x /usr/bin/vinagre ]]
then
  VIEWER="/usr/bin/vinagre --geometry $GEOMETRY localhost::5902"
  echo    "using: $VIEWER"
  echo -e " NOTE: For better performance install ssvncviewer!\n\n"
else
  echo "no VNC viewer found!"
  exit
fi

# make sure there are no existing x11vnc servers running
# NOTE: this assumes you have exlusive remote access to x11vnc!!!

R=$($SSH $REMOTE "which x11vnc" 2>&1 )
S=$($SSH $REMOTE "which ssh-askpass" 2>&1 )
if [[ ${#R} == 0 ]] || [[ ${#S} == 0 ]]
then
  echo "x11vnc or ssh-askpass was not found on $REMOTE!!" 
  echo "Do you want me to try to apt-get install them?"
  select yn in "Yes" "No" 
  do
    case $yn in
      Yes ) echo "ok, I will"; 
            echo "running apt-get on $REMOTE"
            $SSH $REMOTE -t sudo apt-get install ssh-askpass-gnome x11vnc \
              || abort "apt-get failed"
            break;;
      No  ) echo "ok, I won't"; exit;;
    esac
  done
elif [[ $R != "/usr/bin/x11vnc" ]]
then
  abort "failed to connect to $REMOTE"
fi


kill_x11vnc
echo -e "launching remote x11vnc: $REMX\n\n"

RUSER=$($SSH $REMOTE who | grep tty7 | awk '{print $1}')
if [[ ${#RUSER} -gt 0 ]]
then
  echo -e "user $RUSER already logged in, starting x11vnc as user\n"
  $SSH -t $FWD $REMOTE "$UREMX" || abort "failed to background ssh tunnel"
else
  echo -e "no user logged in, starting x11vnc as root\n"
  AUTH=$($SSH $REMOTE ps -efa | grep auth | grep -v grep \
    awk '{print $11}')
  $SSH $FWDX $REMOTE "$RREMX" || abort "failed to background ssh tunnel"
fi

# wait up to 30 seconds for tunnel
echo -e "wait up to 30s for tunnel\n"
let t=30
while (( $t ))
do
  A=$(echo quit | nc localhost 5902) 2>>/dev/null
  if [[ "$A" != "RFB 003.008" ]]
  then
    sleep 2
    let t=t-1
  else
    echo -e "launching viewer\n"
    $VIEWER 
    break
  fi
done

sleep 2
echo -e "cleaning up\n"

#pkill -P $ME -u $(whoami) ssh  >>/dev/null 2>&1
#pkill -P 1 -u $(whoami) ssh  >>/dev/null 2>&1
kill_x11vnc

echo -e "exit $0\n"
