#!/bin/sh /etc/rc.common

START=90
STOP=10

USE_PROCD=1
PROG=/usr/lib/ipsec/charon

. $IPKG_INSTROOT/lib/functions.sh
. $IPKG_INSTROOT/lib/functions/network.sh
. $IPKG_INSTROOT/usr/share/libubox/jshn.sh

STRONGSWAN_CONF_FILE=/etc/strongswan.conf
STRONGSWAN_VAR_CONF_FILE=/var/ipsec/strongswan.conf

SWANCTL_CONF_FILE=/etc/swanctl/swanctl.conf
SWANCTL_VAR_CONF_FILE=/var/swanctl/swanctl.conf

WAIT_FOR_INTF=0

CONFIG_FAIL=0

time2seconds() {
	local timestring="$1"
	local multiplier number suffix

	suffix="${timestring//[0-9 ]}"
	number="${timestring%%$suffix}"
	[ "$number$suffix" != "$timestring" ] && return 1
	case "$suffix" in
	""|s)
		multiplier=1 ;;
	m)
		multiplier=60 ;;
	h)
		multiplier=3600 ;;
	d)
		multiplier=86400 ;;
	*)
		return 1 ;;
	esac
	echo $(( number * multiplier ))
}

seconds2time() {
	local seconds="$1"

	if [ $seconds -eq 0 ]; then
		echo "0s"
	elif [ $((seconds % 86400)) -eq 0 ]; then
		echo "$((seconds / 86400))d"
	elif [ $((seconds % 3600)) -eq 0 ]; then
		echo "$((seconds / 3600))h"
	elif [ $((seconds % 60)) -eq 0 ]; then
		echo "$((seconds / 60))m"
	else
		echo "${seconds}s"
	fi
}

file_reset() {
	: > "$1"
}

xappend() {
	local file="$1"
	shift

	echo "$@" >> "$file"
}

swan_reset() {
	file_reset "$STRONGSWAN_VAR_CONF_FILE"
}

swan_xappend() {
	xappend "$STRONGSWAN_VAR_CONF_FILE" "$@"
}

swan_xappend0() {
	swan_xappend "$@"
}

swan_xappend1() {
	swan_xappend "  ""$@"
}

swan_xappend2() {
	swan_xappend "    ""$@"
}

swan_xappend3() {
	swan_xappend "      ""$@"
}

swan_xappend4() {
	swan_xappend "        ""$@"
}

swanctl_reset() {
	file_reset "$SWANCTL_VAR_CONF_FILE"
}

swanctl_xappend() {
	xappend "$SWANCTL_VAR_CONF_FILE" "$@"
}

swanctl_xappend0() {
	swanctl_xappend "$@"
}

swanctl_xappend1() {
	swanctl_xappend "  ""$@"
}

swanctl_xappend2() {
	swanctl_xappend "    ""$@"
}

swanctl_xappend3() {
	swanctl_xappend "      ""$@"
}

swanctl_xappend4() {
	swanctl_xappend "        ""$@"
}

warning() {
	echo "WARNING: $@" >&2
}

fatal() {
	echo "ERROR: $@" >&2
	CONFIG_FAIL=1
}

append_var() {
	local var="$2" value="$1" delim="${3:- }"
	append "$var" "$value" "$delim"
}

is_aead() {
	local cipher="$1"

	case "$cipher" in
	aes*gcm*|aes*ccm*|aes*gmac*)
		return 0 ;;
	chacha20poly1305)
		return 0 ;;
	esac

	return 1
}

add_esp_proposal() {
	local encryption_algorithm
	local hash_algorithm
	local dh_group

	config_get encryption_algorithm "$1" encryption_algorithm
	config_get hash_algorithm "$1" hash_algorithm
	config_get dh_group "$1" dh_group

	# check for AEAD and clobber hash_algorithm if set
	if is_aead "$encryption_algorithm" && [ -n "$hash_algorithm" ]; then
		fatal "Can't have $hash_algorithm with $encryption_algorithm"
		hash_algorithm=
	fi

	[ -n "$encryption_algorithm" ] && \
		crypto="${crypto:+${crypto},}${encryption_algorithm}${hash_algorithm:+-${hash_algorithm}}${dh_group:+-${dh_group}}"
}

parse_esp_proposal() {
	local conf="$1"
	local var="$2"

	local crypto=""

	config_list_foreach "$conf" crypto_proposal add_esp_proposal

	export -n "$var=$crypto"
}

add_ike_proposal() {
	local encryption_algorithm
	local hash_algorithm
	local dh_group
	local prf_algorithm

	config_get encryption_algorithm "$1" encryption_algorithm
	config_get hash_algorithm "$1" hash_algorithm
	config_get dh_group "$1" dh_group
	config_get prf_algorithm "$1" prf_algorithm

	# check for AEAD and clobber hash_algorithm if set
	if is_aead "$encryption_algorithm" && [ -n "$hash_algorithm" ]; then
		fatal "Can't have $hash_algorithm with $encryption_algorithm"
		hash_algorithm=
	fi

	[ -n "$encryption_algorithm" ] && \
		crypto="${crypto:+${crypto},}${encryption_algorithm}${hash_algorithm:+-${hash_algorithm}}${prf_algorithm:+-${prf_algorithm}}${dh_group:+-${dh_group}}"
}

parse_ike_proposal() {
	local conf="$1"
	local var="$2"

	local crypto=""

	config_list_foreach "$conf" crypto_proposal add_ike_proposal

	export -n "$var=$crypto"
}

config_child() {
	# Generic ipsec conn section shared by tunnel and transport
	local config_name="$1"
	local mode="$2"

	local hw_offload
	local interface
	local ipcomp
	local priority
	local local_subnet
	local local_nat
	local updown
	local firewall
	local remote_subnet
	local lifetime
	local dpdaction
	local closeaction
	local startaction
	local if_id
	local rekeytime
	local rekeybytes
	local lifebytes
	local rekeypackets
	local lifepackets

	config_get startaction "$1" startaction "route"
	config_get local_nat "$1" local_nat ""
	config_get updown "$1" updown ""
	config_get firewall "$1" firewall ""
	config_get lifetime "$1" lifetime ""
	config_get dpdaction "$1" dpdaction "none"
	config_get closeaction "$1" closeaction "none"
	config_get if_id "$1" if_id ""
	config_get rekeytime "$1" rekeytime ""
	config_get_bool ipcomp "$1" ipcomp 0
	config_get interface "$1" interface ""
	config_get hw_offload "$1" hw_offload ""
	config_get priority "$1" priority ""
	config_get rekeybytes "$1" rekeybytes ""
	config_get lifebytes "$1" lifebytes ""
	config_get rekeypackets "$1" rekeypackets ""
	config_get lifepackets "$1" lifepackets ""

	config_list_foreach "$1" local_subnet append_var local_subnet ","
	config_list_foreach "$1" remote_subnet append_var remote_subnet ","

	local esp_proposal
	parse_esp_proposal "$1" esp_proposal

	# translate from ipsec to swanctl
	case "$startaction" in
	add)
		startaction="none" ;;
	route)
		startaction="trap" ;;
	start|none|trap)
		# already using new syntax
		;;
	*)
		fatal "Startaction $startaction unknown"
		startaction=
		;;
	esac

	case "$closeaction" in
	none|clear)
		closeaction="none" ;;
	hold)
		closeaction="trap" ;;
	restart)
		closeaction="start" ;;
	trap|start)
		# already using new syntax
		;;
	*)
		fatal "Closeaction $closeaction unknown"
		closeaction=
		;;
	esac

	[ -n "$closeaction" -a "$closeaction" != "none" ] && warning "Closeaction $closeaction can cause instability"

	case "$dpdaction" in
	none)
		dpddelay="0s"
		dpdaction=
		;;
	clear)
		;;
	hold)
		dpdaction="trap" ;;
	restart)
		dpdaction="start" ;;
	trap|start)
		# already using new syntax
		;;
	*)
		fatal "Dpdaction $dpdaction unknown"
		dpdaction=
		;;
	esac

	case "$hw_offload" in
	yes|no|auto|"")
		;;
	*)
		fatal "hw_offload value $hw_offload invalid"
		hw_offload=""
		;;
	esac

	[ -n "$local_nat" ] && local_subnet="$local_nat"

	swanctl_xappend3 "$config_name {"

	[ -n "$local_subnet" ] && swanctl_xappend4 "local_ts = $local_subnet"
	[ -n "$remote_subnet" ] && swanctl_xappend4 "remote_ts = $remote_subnet"

	[ -n "$hw_offload" ] && swanctl_xappend4 "hw_offload = $hw_offload"
	[ $ipcomp -eq 1 ] && swanctl_xappend4 "ipcomp = 1"
	[ -n "$interface" ] && swanctl_xappend4 "interface = $interface"
	[ -n "$priority" ] && swanctl_xappend4 "priority = $priority"
	[ -n "$if_id" ] && { swanctl_xappend4 "if_id_in = $if_id" ; swanctl_xappend4 "if_id_out = $if_id" ; }
	[ -n "$startaction" -a "$startaction" != "none" ] && swanctl_xappend4 "start_action = $startaction"
	[ -n "$closeaction" -a "$closeaction" != "none" ] && swanctl_xappend4 "close_action = $closeaction"
	swanctl_xappend4 "esp_proposals = $esp_proposal"
	swanctl_xappend4 "mode = $mode"

	if [ -n "$lifetime" ]; then
		swanctl_xappend4 "life_time = $lifetime"
	elif [ -n "$rekeytime" ]; then
		lifetime=$(time2seconds $rekeytime)
		lifetime=$((110 * $lifetime / 100))
		lifetime=$(seconds2time $lifetime)
		swanctl_xappend4 "life_time = $lifetime"
		#swanctl_xappend4 "life_time = $(seconds2time $(((110 * $(time2seconds $rekeytime)) / 100)))"
	fi
	[ -n "$rekeytime" ] && swanctl_xappend4 "rekey_time = $rekeytime"
	if [ -n "$lifebytes" ]; then
		swanctl_xappend4 "life_bytes = $lifebytes"
	elif [ -n "$rekeybytes" ]; then
		swanctl_xappend4 "life_bytes = $(((110 * rekeybytes) / 100))"
	fi
	[ -n "$rekeybytes" ] && swanctl_xappend4 "rekey_bytes = $rekeybytes"
	if [ -n "$lifepackets" ]; then
		swanctl_xappend4 "life_packets = $lifepackets"
	elif [ -n "$rekeypackets" ]; then
		swanctl_xappend4 "life_packets = $(((110 * rekeypackets) / 100))"
	fi
	[ -n "$rekeypackets" ] && swanctl_xappend4 "rekey_packets = $rekeypackets"
	[ -n "$inactivity" ] && swanctl_xappend4 "inactivity = $inactivity"

	[ -n "$updown" ] && swanctl_xappend4 "updown = $updown"
	[ -n "$dpdaction" ] && swanctl_xappend4 "dpd_action = $dpdaction"

        swanctl_xappend3 "}"
}

config_tunnel() {
	config_child "$1" "tunnel"
}

config_transport() {
	config_child "$1" "transport"
}

config_connection() {
	local config_name="$1"

	local enabled
	local gateway
	local local_gateway
	local local_sourceip
	local local_ip
	local remote_gateway
	local pre_shared_key
	local auth_method
	local local_auth
	local remote_auth
	local keyingtries
	local dpddelay
	local inactivity
	local keyexchange
	local fragmentation
	local mobike
	local encap
	local local_cert
	local local_key
	local ca_cert
	local rekeytime

	config_get_bool enabled "$1" enabled 0
	[ $enabled -eq 0 ] && return

	config_get gateway "$1" gateway
	config_get pre_shared_key "$1" pre_shared_key
	config_get auth_method "$1" authentication_method
	config_get local_auth "$1" local_auth "$auth_method"
	config_get remote_auth "$1" remote_auth "$auth_method"
	config_get local_id_eap "$1" local_id_eap ""
	config_get local_identifier "$1" local_identifier ""
	config_get remote_identifier "$1" remote_identifier ""
	config_get local_ip "$1" local_ip "%any"
	config_get keyingtries "$1" keyingtries "3"
	config_get dpddelay "$1" dpddelay "30s"
	config_get inactivity "$1" inactivity
	config_get keyexchange "$1" keyexchange "ikev2"
	config_get fragmentation "$1" fragmentation "yes"
	config_get_bool mobike "$1" mobike 1
	config_get_bool encap "$1" encap 0
	config_get local_cert "$1" local_cert ""
	config_get local_key "$1" local_key ""
	config_get ca_cert "$1" ca_cert ""
	config_get rekeytime "$1" rekeytime
	config_get overtime "$1" overtime

	config_list_foreach "$1" local_sourceip append_var local_sourceip ","

	case "$fragmentation" in
	0)
		fragmentation="no" ;;
	1)
		fragmentation="yes" ;;
	yes|accept|force|no)
		# already using new syntax
		;;
	*)
		fatal "Fragmentation $fragmentation not supported"
		fragmentation=
		;;
	esac

	[ "$gateway" = "any" ] && remote_gateway="%any" || remote_gateway="$gateway"

	local ipdest
	[ "$remote_gateway" = "%any" ] && ipdest="1.1.1.1" || ipdest="$remote_gateway"
	if ip -o route get $ipdest 2&>1 >/dev/null ; then
		local_gateway=`ip -o route get $ipdest | awk '/ src / { gsub(/^.* src /,""); gsub(/ .*$/, ""); print $0}'`
	fi

	#if local_ip is an network.interface name
	local IP
	for ifc in $(ubus list network.interface.*) ; do 
		[[ $ifc =~ network.interface.$local_ip.* ]] || continue
		local GW
		if ! ip -6 route get $gateway 2>&1 >/dev/null | grep -q Error ; then
			json_load "$(ubus call $ifc status)"
			json_get_var up up
			json_select "ipv6_address"
			json_get_keys keys
			local masklow=0
			local IP
			for key in $keys ; do
				json_select $key
				json_get_var preferred preferred 0
				json_get_var mask mask
				if [ $preferred -gt 0 -a $mask -gt $masklow ] ; then
					masklow=$mask
					json_get_var IP address
					MASK=$mask
				elif [ -z $IP ] ; then
					masklow=$mask
					json_get_var IP address
					MASK=$mask
				fi
				json_select ..
			done
			json_select ..
			json_select "route"
			json_get_keys keys
			for key in $keys ; do
				json_select $key
				json_get_var TARGET target
				json_get_var SOURCE source
				if [ "$TARGET" == "::" -a  "$SOURCE" == "$IP/$MASK" ] ; then
						json_get_var GW nexthop
				fi
				json_select ..
			done
			json_select ..
			json_cleanup
			if [ ! -z $IP ] ; then
				local_ip="$IP"
				local_gateway="$GW"
			fi
		elif ! ip -4 route get $gateway 2>&1 >/dev/null | grep -q Error ; then
			eval $(ubus call $ifc status | jsonfilter -e 'IP=$["ipv4-address"][0].address')
			if [ ! -z $IP ] ; then
				local_ip="$IP"
				eval $(ubus call $ifc status | jsonfilter -e 'GW=$["route"][0].nexthop')
				local_gateway="$GW"
			fi
		fi
	done

	if [ -n "$local_key" ]; then
		[ "$(dirname "$local_key")" != "." ] && \
		   fatal "local_key $local_key can't be pathname"
		[ -f "/etc/swanctl/private/$local_key" ] || \
		   fatal "local_key $local_key not found"
	fi

	local ike_proposal
	parse_ike_proposal "$1" ike_proposal

	[ -n "$firewall" ] && fatal "Firewall not supported"

	for auth_method in $local_auth $remote_auth ; do
		if [ "$auth_method" = pubkey ]; then
			if [ -n "$ca_cert" ]; then
				[ "$(dirname "$ca_cert")" != "." ] && \
					fatal "ca_cert $ca_cert can't be pathname"
				[ -f "/etc/swanctl/x509ca/$ca_cert" ] || \
					fatal "ca_cert $ca_cert not found"
			fi

			if [ -n "$local_cert" ]; then
				[ "$(dirname "$local_cert")" != "." ] && \
					fatal "local_cert $local_cert can't be pathname"
				[ -f "/etc/swanctl/x509/$local_cert" ] || \
					fatal "local_cert $local_cert not found"
			fi
		fi
	done

	swanctl_xappend0 "# config for $config_name"
	swanctl_xappend0 "connections {"
	swanctl_xappend1 "$config_name {"
	swanctl_xappend2 "local_addrs = $local_ip"
	swanctl_xappend2 "remote_addrs = $remote_gateway"

	[ -n "$local_sourceip" ] && swanctl_xappend2 "vips = $local_sourceip"
	[ -n "$fragmentation" ] && swanctl_xappend2 "fragmentation = $fragmentation"

	swanctl_xappend2 "local {"
	swanctl_xappend3 "auth = $local_auth"
	[ -n "$local_id_eap" ] && swanctl_xappend3 "eap_id = \"$local_id_eap\""
	[ -n "$local_identifier" ] && swanctl_xappend3 "id = \"$local_identifier\""
	[ "$local_auth" = pubkey ] && [ -n "$local_cert" ] && \
	    swanctl_xappend3 "certs = $local_cert"
	swanctl_xappend2 "}"

	swanctl_xappend2 "remote {"
	swanctl_xappend3 "auth = $remote_auth"
	[ -n "$remote_identifier" ] && swanctl_xappend3 "id = \"$remote_identifier\""
	swanctl_xappend2 "}"

	swanctl_xappend2 "children {"

	config_list_foreach "$1" tunnel config_tunnel

	config_list_foreach "$1" transport config_transport

	swanctl_xappend2 "}"

	case "$keyexchange" in
	ike)
		;;
	ikev1)
		swanctl_xappend2 "version = 1" ;;
	ikev2)
		swanctl_xappend2 "version = 2" ;;
	*)
		fatal "Keyexchange $keyexchange not supported"
		keyexchange=
		;;
	esac

	[ $mobike -eq 1 ] && swanctl_xappend2 "mobike = yes" || swanctl_xappend2 "mobike = no"
	[ $encap -eq 1 ] && swanctl_xappend2 "encap = yes"

	if [ -n "$rekeytime" ]; then
		swanctl_xappend2 "rekey_time = $rekeytime"

		if [ -z "$overtime" ]; then
			overtime=$(seconds2time $(($(time2seconds $rekeytime) / 10)))
		fi
	fi
	[ -n "$overtime" ] && swanctl_xappend2 "over_time = $overtime"

	swanctl_xappend2 "proposals = $ike_proposal"
	[ -n "$dpddelay" ] && swanctl_xappend2 "dpd_delay = $dpddelay"
	[ "$keyingtries" = "%forever" ] && swanctl_xappend2 "keyingtries = 0" || swanctl_xappend2 "keyingtries = $keyingtries"

	swanctl_xappend1 "}"
	swanctl_xappend0 "}"
	[ $local_auth = $remote_auth ] && remote_auth=""
	for auth_method in $local_auth $remote_auth ; do
		if [ "$auth_method" = pubkey ]; then
			swanctl_xappend0 ""

			if [ -n "$ca_cert" ]; then
				swanctl_xappend0 "authorities {"
				swanctl_xappend1 "$config_name {"
				swanctl_xappend2 "cacert = $ca_cert"
				swanctl_xappend1 "}"
				swanctl_xappend0 "}"
			fi

		elif [ "$auth_method" = psk ]; then
			swanctl_xappend0 ""

			swanctl_xappend0 "secrets {"
			swanctl_xappend1 "ike {"
			swanctl_xappend2 "secret = $pre_shared_key"
			if [ -n "$local_id" ]; then
				swanctl_xappend2 "id1 = $local_id"
				if [ -n "$remote_id" ]; then
					swanctl_xappend2 "id2 = $remote_id"
				fi
			fi
			swanctl_xappend1 "}"
			swanctl_xappend0 "}"
		elif [ "$auth_method" = eap ]; then
			swanctl_xappend0 ""

			swanctl_xappend0 "secrets {"
			swanctl_xappend1 "eap {"
			swanctl_xappend2 "secret = $pre_shared_key"
			swanctl_xappend2 "id = $local_id_eap"
			swanctl_xappend1 "}"
			swanctl_xappend0 "}"
		else
			fatal "AuthenticationMode $auth_mode not supported"
		fi
	done

	swanctl_xappend0 ""
}

do_preamble() {
	swanctl_xappend0 "# generated by /etc/init.d/swanctl"
}

config_ipsec() {
	local rtinstall_enabled
	local routing_table
	local routing_table_id
	local interface


	config_get debug "$1" debug 0
	config_get_bool rtinstall_enabled "$1" rtinstall_enabled 1
	[ $rtinstall_enabled -eq 1 ] && install_routes=yes || install_routes=no

	# prepare extra charon config option ignore_routing_tables
	for routing_table in $(config_get "$1" "ignore_routing_tables"); do
		if [ "$routing_table" -ge 0 ] 2>/dev/null; then
			routing_table_id=$routing_table
		else
			routing_table_id=$(sed -n '/[ \t]*[0-9]\+[ \t]\+'$routing_table'[ \t]*$/s/[ \t]*\([0-9]\+\).*/\1/p' /etc/iproute2/rt_tables)
		fi

		[ -n "$routing_table_id" ] && append routing_tables_ignored "$routing_table_id"
	done

	config_list_foreach "$1" interface append_var interface_list

	if [ -z "$interface_list" ]; then
		WAIT_FOR_INTF=0
	else
		for interface in $interface_list; do
			network_get_device device $interface
			[ -n "$device" ] && append device_list "$device" ","
		done
		[ -n "$device_list" ] && WAIT_FOR_INTF=0 || WAIT_FOR_INTF=1
	fi
}

do_postamble() {
	swan_xappend0 "# generated by /etc/init.d/swanctl"
	swan_xappend0 "charon {"
	swan_xappend1 "make_before_break = yes"
	swan_xappend1 "install_routes = $install_routes"
	[ -n "$routing_tables_ignored" ] && swan_xappend1 "ignore_routing_tables = $routing_tables_ignored"
	[ -n "$device_list" ] && swan_xappend1 "interfaces_use = $device_list"
	swan_xappend1 "start-scripts {"
	swan_xappend2 "load-all = /usr/sbin/swanctl --load-all --noprompt"
	swan_xappend1 "}"
	swan_xappend1 "syslog {"
	swan_xappend2 "identifier = ipsec"
	swan_xappend2 "daemon {"
	swan_xappend3 "default = $debug"
	swan_xappend2 "}"
	swan_xappend1 "}"
	swan_xappend0 "}"
}

prepare_env() {
	mkdir -p /var/ipsec /var/swanctl

	swan_reset
	swanctl_reset
	do_preamble

	# needed by do_postamble
	local debug install_routes routing_tables_ignored device_list interface_list

	config_load ipsec
	config_foreach config_ipsec ipsec
	config_foreach config_connection remote

	do_postamble
}

service_running() {
	swanctl --stats > /dev/null 2>&1
}

reload_service() {
	running && {
		prepare_env
		[ $WAIT_FOR_INTF -eq 0 ] && {
			swanctl --load-all --noprompt
			return
		}
	}

	start
}

stop_service() {
	swan_reset
	swanctl_reset
}

service_triggers() {
	#3s delay after ifup
	PROCD_RELOAD_DELAY="3000"
	procd_add_reload_trigger "ipsec"
	interfaces=$(uci get ipsec.@ipsec[-1].interface)
	for interface in $interfaces ; do
		procd_add_interface_trigger "interface.*" "$interface" /etc/init.d/ipsec restart
	done
}

start_service() {
	prepare_env

	[ $WAIT_FOR_INTF -eq 1 ] && return

	if [ $CONFIG_FAIL -ne 0 ]; then
		procd_set_param error "Invalid configuration"
		return
	fi

	procd_open_instance

	procd_set_param command $PROG

	procd_set_param file $SWANCTL_CONF_FILE
	procd_append_param file /etc/swanctl/conf.d/*.conf
	procd_append_param file $STRONGSWAN_CONF_FILE

	procd_set_param respawn

	procd_close_instance
}

boot() {
	mkdir -p "$(dirname $STRONGSWAN_VAR_CONF_FILE)"
	mkdir -p "$(dirname $SWANCTL_VAR_CONF_FILE)"
	if [ ! -L /etc/swanctl/x509ca ] ; then
		rm -rf /etc/swanctl/x509ca
		ln -s /etc/ssl/certs /etc/swanctl/x509ca
	fi
	/etc/init.d/swanctl disable
	#TODO
	#uci del_list network.lan.ip6class="tunnel1prefix"
	#interfaces=$(uci get ipsec.@ipsec[-1].interface)
	#for interface in $interfaces ; do
	#	uci del_list network.lan.ip6class="$interface"
	#	uci add_list network.lan.ip6class="$interface"
	#done
	#uci commit network
	( sleep 60 ; /etc/init.d/ipsec start ) &
}
