export RBDIR="/usr/lib/redborder"
export RBBIN="${RBDIR}/bin"
export RBLIB="${RBDIR}/lib"
export RBETC="/etc/redborder"
export PATH=$PATH:$RBBIN
export EDITOR=vim
export JAVA_HOME=/usr/lib/jvm/jre
export RAILS_ENV=production
alias bwm-ng='bwm-ng -u bits -t 1000 -d'
alias log='tail -n 200 -f'

# Send History to syslog
PROMPT_COMMAND=$(history -a)
typeset -r PROMPT_COMMAND
function log2syslog
{
	declare command
	command=$BASH_COMMAND
	logger -p local1.notice -t bash -i -- $USER : $PWD : $command
}
trap log2syslog DEBUG

# Banner
figlet -f slant "redborder-ng"
echo ""
