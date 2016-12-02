export RBDIR="/usr/lib/redborder"
export RBBIN="${RBDIR}/bin"
export RBLIB="${RBDIR}/lib"
export RBETC="/etc/redborder"
export PATH=$PATH:$RBBIN
export EDITOR=vim
export JAVA_HOME=/usr/lib/jvm/jre
alias bwm-ng='bwm-ng -u bits -t 1000 -d'
alias log='tail -n 200 -f'
# Banner
figlet -f slant "redborder-ng"
echo ""
