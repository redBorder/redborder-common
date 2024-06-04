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
function lv() {
    vim $(locate $1 | grep $2""$ | head -n 1)
}

# Send History to syslog
function log2syslog
{
	declare command
	command=$BASH_COMMAND
	case $command in
		printf\ \"*) : ;;
		*) shopt -q login_shell && logger -p local1.notice -t "bash[$$]" -- $USER : $PWD : $command ;;
	esac
}
trap log2syslog DEBUG

# Banner
# figlet -f slant "redborder-ng"
# echo ""
