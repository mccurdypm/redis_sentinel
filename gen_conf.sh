#!/bin/bash

if [[ -z ${NUM_INSTANCES} ]]; then
    source include/redis_y/process_helpers.sh
    setPkgName "redis_y"
fi

if [[ $# -gt 0 ]]; then
    setInstance $1
fi

OLDIFS=$IFS

#------------------------------------------------------------------------------------
# generates the correct key name for the instance variable
# option -nobase :  will not add _1 to the key name for the base instance
# eg.for the first instance the filenames need not have _1 attached
#------------------------------------------------------------------------------------
function generateInstanceKey() {
    local nobase=0
    if [[ $1 == "-nobase" ]] ; then nobase=1 ; shift; fi
    local key=$1
    key=${key//-/_}
    if isBaseInstance && [[ $nobase == 1 ]]; then
        echo -en ${key}
    else
        echo -en ${key}_${IPORT}
    fi
}

function printRenameCommand() {
    local data=$(getValue rename_command)
    IFS=',' arr=($data); IFS=$OLDIFS
    local i
    for (( i=0; i<${#arr[*]}; i++))
    do
        echo "rename-command ${arr[$i]}"
    done
    if [[ 0 == ${#arr[*]} ]] ; then
        comment "[skipped] : rename-command"
    fi
}

function printSave() {
    local data=$(getValue save "900 1,300 10,60 10000")
    IFS=',' arr=($data) ;IFS=$OLDIFS
    local i;
    for (( i=0 ; i < ${#arr[*]} ; i++ ))
    do
        echo "save ${arr[$i]}"
    done
    if [[ 0 == ${#arr[*]} ]] ; then
        comment "[skipped] : save"
    fi
}

function printClientOutputBuffer() {
    local data=$(getValue client-output-buffer-limit "normal 0 0 0,pubsub 32mb 8mb 60,slave 256mb 64mb 60")
    IFS=',' arr=($data) ;IFS=$OLDIFS
    local i;
    for (( i=0 ; i < ${#arr[*]}; i++ ))
    do
        echo "client-output-buffer-limit ${arr[$i]}"
    done
    if [[ 0 == ${#arr[*]} ]] ; then
        comment "[skipped] : client-output-buffer-limit"
    fi
}

function printSlaveOf() {
    local value=$(getValue slaveof)
    local host;
    local mport=6379;

    if [[ $value =~ ^# ]] || isEmpty $value ; then
        comment "[skipped] : slaveof"
        return 0
    fi
    if [[ $value =~ slaveof ]]; then
        # this is the old format

        IFS=' ' arr=($value) ;IFS=$OLDIFS
        host=${arr[1]}
        mport=${arr[2]}
        comment "old format : $value : ${arr[1]}-${arr[2]}"
    else
        IFS=':' arr=($value) ;IFS=$OLDIFS
        host=${arr[0]}
        mport=${arr[1]}
    fi

    #special case for all slaves in a multi instance
    hosts=($(rangeexpand $value))
    if isMultiInstance && [[ ${#hosts[*]} -gt 1 ]]; then
        comment "special case of all slaves"
        hosts=($(rangeexpand $value))
        if [[ ${#hosts[*]} -ne ${NUM_INSTANCES} ]]; then
            echo "--- ERROR : slaveof range expansion count [ ${#hosts[@]} ] != instance count [${NUM_INSTANCES}]"
        else
            num=$((INSTANCE_NUM-1))
            hostport=${hosts[$num]}
            IFS=':' arr=($hostport) ;IFS=$OLDIFS
            host=${arr[0]}
            mport=${arr[1]}                
        fi
    fi

    if isEmpty $mport ; then mport=6379 ; fi
    
    if isEmpty $host; then
        echo "--- ERROR : slaveof host - not specified "
    else
        echo "slaveof $host $mport"
    fi
    
}

#----------------------------------------------------------------------------
# Begin Configuration
#----------------------------------------------------------------------------

if isMultiInstance ; then
    section "Redis Config : for instance [${INSTANCE_NUM}] of [${NUM_INSTANCES}]"
else
    section "Redis Config"
fi

IPORT=$(getValue -nobase port $((port+${INSTANCE_NUM}-1)))

printval activerehashing yes

printval appendfsync everysec
printval appendonly no
echo "appendfilename $(generateInstanceKey -nobase appendonly).aof"

#printval auto-aof-rewrite-min-size 64mb
printval auto-aof-rewrite-percentage 100

printval -ne bind

printClientOutputBuffer

echo "daemonize yes"

printval databases 16

echo "dbfilename $(generateInstanceKey -nobase dump).rdb"

printval dir var/redis
printval hash-max-ziplist-entries 512
printval hash-max-ziplist-value 64
printval list-max-ziplist-entries 512
printval list-max-ziplist-value 64

echo "logfile logs/redis/$(generateInstanceKey -nobase redis).log"

printval loglevel notice
printval lua-time-limit 5000

printsecretval -ne masterauth
printRenameCommand
printval -ne maxclients
printval -ne maxmemory
printval -ne maxmemory-policy
printval -ne maxmemory-samples

printval no-appendfsync-on-rewrite no

echo "pidfile var/run/$(generateInstanceKey -nobase redis).pid"

if isEmpty $port; then port=6379; fi

# special case of disabling tcp listen
if [[ $port != 0 ]] ; then
    echo "port $(getValue -nobase port $((port+${INSTANCE_NUM}-1)) )"
else
    echo "port $(getValue port 0)"
fi

printval rdbchecksum yes
printval rdbcompression yes

printval -ne repl-ping-slave-period
printval -ne repl-timeout
printsecretval -ne requirepass

printval -ne include

printSave

printval set-max-intset-entries 512

printSlaveOf

printval slave-priority 100 
printval slave-read-only yes
printval slave-serve-stale-data yes
printval slowlog-log-slower-than 10000
printval slowlog-max-len 128
printval stop-writes-on-bgsave-error yes

if [[ "yes" == $(getValue syslog-enabled) ]]; then
    printval syslog-enabled no
    printval syslog-ident redis
    printval syslog-facility local0
else
    printval -ne syslog-enabled
    printval -ne syslog-ident 
    printval -ne syslog-facility 
fi
printval timeout 0

printval -ne unixsocket
printval -ne unixsocketperm

printval zset-max-ziplist-entries 128
printval zset-max-ziplist-value 64

section "settings introduced in 2.8"
printval -ne hz
printval -ne aof-rewrite-incremental-fsync 
printval -ne min-slaves-to-write
printval -ne min-slaves-to-write
printval -ne notify-keyspace-events
printval -ne repl-disable-tcp-nodelay
printval -ne repl-backlog-size
printval -ne repl-backlog-ttl
printval -ne tcp-keepalive

section "Cluster settings - Introduced in 3.0.0"
printval -ne cluster-enabled
printval -ne cluster-config-file
printval -ne cluster-node-timeout
printval -ne cluster-slave-validity-factor
printval -ne cluster-migration-barrier
printval -ne cluster-require-full-coverage

files=($(ls -1 conf/redis/include/*.conf 2>/dev/null))

if [[ 0 == ${#files[*]} ]] ; then
    section "No other conf files found ...."
else
    section "Other Include files"

    for file in ${files[*]}
    do
        echo "include $file"
    done
fi
