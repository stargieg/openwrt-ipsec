#!/bin/sh

log() {
	logger -t ipsec $@
}

log "$PLUTO_VERB"

case "$PLUTO_VERB:$1" in
    up-client-v6:)
        log "set ip6 class"
        uci del_list network.lan.ip6class="wan_6"
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
        date >> /tmp/ipsec_up.log
        env >> /tmp/ipsec_up.log
        echo >> /tmp/ipsec_up.log
    ;;
    down-client-v6:)
        log "set ip6 class"
        uci del_list network.lan.ip6class="tunnel1prefix"
        uci add_list network.lan.ip6class="wan_6"
        uci commit network
        log "reload network"
        /etc/init.d/network reload
        #ip -6 route del 64:ff9b::/96 dev wwan0 metric 2
        #ip -6 route del default from "$PLUTO_MY_CLIENT" dev "$PLUTO_INTERFACE"
        ip -6 route del default from "$PLUTO_MY_CLIENT" dev "tunnel1"
        ip -6 route del 64:ff9b::/96 dev tunnel1
        ip route del 10.0.0.0/8 dev "tunnel1"
        ip route del 192.168.0.0/16 dev "tunnel1"
        date >> /tmp/ipsec_down.log
        env >> /tmp/ipsec_down.log
        echo >> /tmp/ipsec_down.log
    ;;
esac



#date >> /tmp/ipsec_updown.log
#env >> /tmp/ipsec_updown.log
#>> /tmp/ipsec_updown.log
#[ "$PLUTO_VERB" == "up-client-v6" ] || exit
#ip -6 route add default from "$PLUTO_MY_SOURCEIP6_1" dev "$PLUTO_INTERFACE"

#ip -6 route add default from 2a0a:51c0:24:200::4 dev wwan0
#PLUTO_PEER_PORT=0
#SHLVL=2
#PLUTO_MY_SOURCEIP=10.10.10.4
#PLUTO_REQID=1
#PLUTO_MY_SOURCEIP4_1=10.10.10.4
#PLUTO_PEER_CLIENT=::/0
#PLUTO_MY_SOURCEIP6_1=2a0a:51c0:24:200::4
#PLUTO_UNIQUEID=1
#PLUTO_PEER=2a0a:51c0:24:10::3
#PLUTO_ME=2a01:599:141:5496:f41a:a9ff:fe34:14a4
#PLUTO_MY_PROTOCOL=0
#PLUTO_PEER_ID=vpn.grikon.net
#PLUTO_VERB=up-client-v6
#PLUTO_INTERFACE=wwan0
#PLUTO_UDP_ENC=4500
#PATH=/usr/sbin:/usr/bin:/sbin:/bin
#PLUTO_MY_PORT=0
#PLUTO_VERSION=1.1
#PLUTO_MY_CLIENT=2a0a:51c0:24:200::4/128
#PLUTO_PEER_PROTOCOL=0
#PWD=/
#PLUTO_CONNECTION=tunnel2
#PLUTO_MY_ID=2a01:599:141:5496:f41a:a9ff:fe34:14a4
#PLUTO_PROTO=esp