#!/bin/sh

log() {
	logger -t ipsec $@
}

log "$PLUTO_VERB"

case "$PLUTO_VERB:$1" in
    up-client-v6:)
        log "set ip6 class"
        interfaces=$(uci get ipsec.@ipsec[-1].interface)
        for interface in $interfaces ; do
            uci del_list network.lan.ip6class="$interface"
        done
        uci add_list network.lan.ip6class="tunnel1prefix"
        uci commit network
        log "reload network"
        /etc/init.d/network reload
        #ip -6 route add default from "$PLUTO_MY_CLIENT" dev "$PLUTO_INTERFACE"
        #ip -6 route add 64:ff9b::/96 dev wwan0 metric 2
        ip -6 route add 64:ff9b::/96 dev tunnel1
        ip -6 route add default from "$PLUTO_MY_CLIENT" dev "tunnel1"
        ip route add 10.0.0.0/8 dev "tunnel1"
        ip route add 192.168.0.0/16 dev "tunnel1"
        #debug output
        #date >> /tmp/ipsec_up.log
        #env >> /tmp/ipsec_up.log
        #echo >> /tmp/ipsec_up.log
    ;;
    down-client-v6:)
        log "set ip6 class"
        uci del_list network.lan.ip6class="tunnel1prefix"
        interfaces=$(uci get ipsec.@ipsec[-1].interface)
        for interface in $interfaces ; do
            uci del_list network.lan.ip6class="$interface"
            uci add_list network.lan.ip6class="$interface"
        done
        uci commit network
        log "reload network"
        /etc/init.d/network reload
        #ip -6 route del 64:ff9b::/96 dev wwan0 metric 2
        #ip -6 route del default from "$PLUTO_MY_CLIENT" dev "$PLUTO_INTERFACE"
        ip -6 route del default from "$PLUTO_MY_CLIENT" dev "tunnel1"
        ip -6 route del 64:ff9b::/96 dev tunnel1
        ip route del 10.0.0.0/8 dev "tunnel1"
        ip route del 192.168.0.0/16 dev "tunnel1"
        #debug output
        #date >> /tmp/ipsec_down.log
        #env >> /tmp/ipsec_down.log
        #echo >> /tmp/ipsec_down.log
    ;;
esac
