#!/bin/bash

source /etc/profile

f_usage() {

    cat <<EOF
Usage: rb_rubywrapper [-c] [-d] [-h] [-e script]
    -c          Create/update links for every ruby script under $RBDIR/scripts directory
    -d          Delete links for every ruby script under $RBDIR/scripts directory
    -s script   Execute the ruby script (applet) under $RBDIR/scripts directory
    -h          Print this help

EOF
}

f_execute() {
    local script=$1
    shift 1
    local args="$@"

    rvm gemset use default &>/dev/null
    
    ret=0
    if [ -e $RBDIR/scripts/$script.rb ]; then
        exec $RBDIR/scripts/$script.rb $args
    else
        echo "Error: script $script does not exist under $RBDIR/scripts directory"
        ret=1
    fi

    return $ret
}

f_update_links() {
    local s
    pushd $RBBIN &>/dev/null
    for s in $(ls $RBDIR/scripts/*.rb 2>/dev/null); do
        s=$(basename $s | sed 's/\.rb$//')
        if [ -e $s ]; then
            continue
        else
            ln -s rb_rubywrapper.sh $s
        fi
    done
    popd &>/dev/null
}

f_delete_links() {
    local s
    pushd $RBBIN &>/dev/null
    for s in $(ls $RBDIR/scripts/*.rb 2>/dev/null); do
        s=$(basename $s | sed 's/\.rb$//')
        if [ -h $s ]; then
            rm -f $s
        else
            continue
        fi
    done
    popd &>/dev/null
}

script=$(basename $0)

ret=0

if [ "x$script" == "xrb_rubywrapper.sh" ]; then
    flag_update_links=0
    flag_delete_links=0
    flag_execute=0
    while getopts "cds:h" opt; do
        case $opt in
    	    c)  flag_update_links=1
                ;;
            d)  flag_delete_links=1
                ;;
            s)  flag_execute=1
                script=$OPTARG
                ;;
    		h)  f_usage
                exit 0
                ;;
            *)  f_usage
                exit 1
                ;;
        esac
    done

    shift $((OPTIND-1))

    if [ $flag_update_links -eq 1 -a $flag_delete_links -eq 1 ]; then
        echo "Error: You cannot use -l and -u at the same time"
        f_usage
        ret=1
    elif [ $flag_update_links -eq 1 ]; then
        f_update_links
        ret=0
    elif [ $flag_delete_links -eq 1 ]; then
        f_delete_links
        ret=0
    elif [ $flag_execute -eq 1 ]; then
        f_execute $script $@
        ret=$?
        if [ $ret -ne 0 ]; then
            f_usage
        fi
    else
        f_usage
        ret=1
    fi
else

    # the applet script was invoked via link
    f_execute $script $@
    ret=$?
    if [ $ret -ne 0 ]; then
        f_usage
    fi
fi

exit $ret

## vim:ts=4:sw=4:expandtab:ai:nowrap:formatoptions=croqln:
