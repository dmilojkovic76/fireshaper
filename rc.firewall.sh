#!/bin/sh
#################################################################################
#  /etc/rc.d/rc.firewall    Skripta za podesavanje Rutiranja Interneta	v0.20   #
#                           prvi put napisana 16.02.2006.                       #
#                                                                               #
#   d00mil 15.09.2007.                              d00mil.d00mil@gmail.com     #
##
#										#
#  Sintaksa za iptables je u sustini:						#
#										#
#	iptables [-t table] -ACDI CHAIN rule-specifikacija -j TARGET [opcije]	#
#################################################################################

function setup_fn
{
verzija="0.20"
IPTABLES=`which iptables`
IFCONFIG=`which ifconfig`
DEPMOD=`which depmod`
LSMOD=`which lsmod`
MODPROBE=`which modprobe`
GREP=`which grep`
AWK=`which awk`
SED=`which sed`
CUT=`which cut`
TR=`which tr`
CAT=`which cat`

#FIXME: Pronadji bolji nacin za proveru aktivnosti konekcije
if ! [ -e /proc/sys/net/ipv4/conf/ppp0 ]; then
    /usr/sbin/pppoe-start
    sleep 8
fi

# Internet (adsl modem) konfiguracija (DHCP):
INET_IFACE="ppp0"
INET_IP=`($IFCONFIG $INET_IFACE | $GREP inet | $AWK '{ print $2 }' | $CUT -b 6-20)`
INET_BROADCAST=`($IFCONFIG $INET_IFACE | $GREP inet | $AWK '{ print $3 }' | $CUT -b 7-21)`

# Local Area Network konfiguracija (192.168.0.1):
LAN_IFACE="eth1"
LAN_IP="192.168.0.1"
LAN_IP_RANGE="192.168.0.0/24"
#LAN_BROADCAST=`($IFCONFIG $LAN_IFACE | $GREP inet | $AWK '{ print $3 }' | $CUT -b 7-21)`
LAN_BROADCAST="192.168.0.255"
$IFCONFIG $LAN_IFACE promisc arp

# Local Wireless Area Network konfiguracija (192.168.100.1):
WiFi_IFACE="ra0"
WiFi_IP="192.168.100.1"
WiFi_IP_RANGE="192.168.100.0/24"
#WiFi_BROADCAST=`($IFCONFIG $WiFi_IFACE | $GREP inet | $AWK '{ print $3 }' |$CUT -b 7-21)`
WiFi_BROADCAST="192.168.100.255"
$IFCONFIG $WiFi_IFACE promisc arp

# Loaclhost konfiguracija:
LO_IFACE="lo"
LO_IP="127.0.0.1"

# Portovi za forwardovanje:
TCP_PORTS="21,22,25,80,113,443,3389,3724,6112,6881,7741"
UDP_PORTS="53,123,443,2074,4000,7741"

# d00mil:
D_IP="192.168.0.2"
D_TCP_PORTS="46411,46661,46881,6969,7000,5400"
D_UDP_PORTS="46411,46664,46881"

# Srdjan:
S_IP="192.168.0.3"
S_TCP_PORTS="46511,46671,46882"
S_UDP_PORTS="46511,46674,46882"

# IBM_ThinkPad:
I_IP="192.168.100.2"
I_TCP_PORTS="46611,46681,46771"
I_UDP_PORTS="46611,46684,46771"
}

function moduli_fn
{
# Ucitavanje potrebnih modula:
$DEPMOD -a
for osnovni_moduli in ip_tables ip_conntrack iptable_filter iptable_mangle iptable_nat \
	 ipt_LOG ipt_limit ipt_state
do
  if ! $LSMOD | $GREP -q $osnovni_moduli; then
    $MODPROBE $osnovni_moduli
  fi
done

# Neobavezni moduli ali potencijalno potrebni:
for ostali_moduli in ipt_owner ipt_REJECT ipt_MASQUERADE ip_conntrack_ftp ip_conntrack_irc \
	 ip_nat_ftp ip_nat_irc
do
  if ! $LSMOD | $GREP -q $ostali_moduli; then
    $MODPROBE $ostali_moduli
  fi
done
}

function hakeraj_fn
{
## Ukljucujem ip forwarding:
if [ -e /proc/sys/net/ipv4/ip_forward ]; then
   echo 1 > /proc/sys/net/ipv4/ip_forward
fi

## Stelovanje za dinamicku adresu
if [ -e /proc/sys/net/ipv4/ip_dynaddr ]; then
    echo 1 > /proc/sys/net/ipv4/ip_dynaddr
fi

#FIXME: Proveri ovo dole jedno po jedno

## no IP spoofing: Ukljuci 'Reverse Path FIltering'. Ovo je 'Full' a moze i echo 1 > $i
#if [ -e /proc/sys/net/ipv4/conf/all/rp_filter ] ; then
#    for i in /proc/sys/net/ipv4/conf/*/rp_filter; do
#	echo 2 > $i
#    done
#fi

## Stelovanje za ponasanje kao denial-of-service alat
#if [ -e /proc/sys/net/ipv4/icmp_echo_ignore_broadcasts ]; then
#    echo 1 > /proc/sys/net/ipv4/icmp_echo_ignore_broadcasts
#fi

## Kada  dodje do prepunjenja TCP servisa zbog ogromnog broja dolazecih konekcija posalji RST pakete.
#if [ -e /proc/sys/net/ipv4/tcp_abort_on_overflow ]; then
#    echo 1 > /proc/sys/net/ipv4/tcp_abort_on_overflow
#fi
}

function info_fn
{
printf "\033[40m\033[1;34m=============================================================================\033[0m\n"
printf "\033[40m\033[1;34m          d00mil's IPTables Firewall Script $verzija\033[0m\n"
printf "\033[40m\033[1;34m=============================================================================\033[0m\n"
echo
printf "\033[40m\033[1;31m    Inet iface: $INET_IFACE inet addr: $INET_IP Bcast: $INET_BROADCAST\033[0m\n"
printf "\033[40m\033[1;31m    LAN iface: $LAN_IFACE inet addr: $LAN_IP Bcast: $LAN_BROADCAST\033[0m\n"
printf "\033[40m\033[1;31m    WiFi iface: $WiFi_IFACE inet addr: $WiFi_IP Bcast: $WiFi_BROADCAST\033[0m\n"
echo
}

function start_fn {
### RULES SET-UP ###
printf "\033[40m\033[1;31m   ########## START FIREWALL ##########\033[0m\n"

for i in filter nat mangle
do
    $IPTABLES --table $i --flush
    $IPTABLES --table $i --delete-chain
done

# Postavljanje polisa:
$IPTABLES -P INPUT DROP
$IPTABLES -P OUTPUT DROP
$IPTABLES -P FORWARD DROP
# Kreiranje User lanaca:
$IPTABLES -N bad_tcp_paketi
$IPTABLES -N allowed
$IPTABLES -N tcp_paketi
$IPTABLES -N udp_paketi
$IPTABLES -N icmp_paketi
## Popuni Userspecified lance:
$IPTABLES -A bad_tcp_paketi -p tcp --tcp-flags SYN,ACK SYN,ACK -m state --state NEW -j REJECT --reject-with tcp-reset
$IPTABLES -A bad_tcp_paketi -p tcp ! --syn -m state --state NEW -j LOG --log-prefix "NEW a nije SYN paket:"
$IPTABLES -A bad_tcp_paketi -p tcp ! --syn -m state --state NEW -j DROP

$IPTABLES -A tcp_paketi -p TCP -j DROP
$IPTABLES -A tcp_paketi -p TCP --syn -j ACCEPT
$IPTABLES -A tcp_paketi -p TCP -m multiport -s 0/0 --destination-port $TCP_PORTS -m state --state ESTABLISHED,RELATED -j ACCEPT
$IPTABLES -A tcp_paketi -p TCP -m multiport -s 0/0 --destination-port $D_TCP_PORTS -m state --state ESTABLISHED,RELATED -j ACCEPT # d00mil
$IPTABLES -A tcp_paketi -p TCP -m multiport -s 0/0 --destination-port $S_TCP_PORTS -m state --state ESTABLISHED,RELATED -j ACCEPT # Srdjan
$IPTABLES -A tcp_paketi -p TCP -m multiport -s 0/0 --destination-port $I_TCP_PORTS -m state --state ESTABLISHED,RELATED -j ACCEPT # IBM_ThinkPad

$IPTABLES -A udp_paketi -p UDP -m multiport -s 0/0 --destination-port $UDP_PORTS -j ACCEPT
$IPTABLES -A udp_paketi -p UDP -m multiport -s 0/0 --destination-port $D_UDP_PORTS -j ACCEPT # d00mil
$IPTABLES -A udp_paketi -p UDP -m multiport -s 0/0 --destination-port $S_UDP_PORTS -j ACCEPT # Srdjan
$IPTABLES -A udp_paketi -p UDP -m multiport -s 0/0 --destination-port $I_UDP_PORTS -j ACCEPT # IBM_ThinkPad

$IPTABLES -A icmp_paketi -p ICMP -s 0/0 --icmp-type 0 -j ACCEPT
$IPTABLES -A icmp_paketi -p ICMP -s 0/0 --icmp-type 8 -j ACCEPT
$IPTABLES -A icmp_paketi -p ICMP -s 0/0 --icmp-type 11 -j ACCEPT

#############
## FIX-evi ##
############
# Odbaci sve pakete koji stizu ja INET_ICAFE a imaju lokalnu adresu:
$IPTABLES -A FORWARD -s $LAN_IP_RANGE -i $INET_IFACE -j DROP
$IPTABLES -A FORWARD -s $WiFi_IP_RANGE -i $INET_IFACE -j DROP
# Odbaci sve neusmerene echo-request pakete:
$IPTABLES -A FORWARD -p icmp --icmp-type echo-request -d $LAN_BROADCAST -j DROP
$IPTABLES -A FORWARD -p icmp --icmp-type echo-request -d $WiFi_BROADCAST -j DROP
# Ogranici broj SYN paketa u jedinici vremena:
$IPTABLES -A FORWARD -p tcp -i $INET_IFACE --syn -m limit --limit 1/s -j ACCEPT
# Ogranici broj SYN i FIN paketa u jedinici vremena:
$IPTABLES -A FORWARD -p tcp --tcp-flags SYN,ACK,FIN,RST SYN -i $INET_IFACE -m limit --limit 1/s -j ACCEPT
# Ogranici broj ICMP echo-request paketa u jedinici vremena:
$IPTABLES -A FORWARD -p icmp --icmp-type echo-request -i $INET_IFACE -m limit --limit 1/s -j ACCEPT
# MS Network multicast flood fix:
$IPTABLES -A INPUT -i $INET_IFACE -d 244.0.0.0/8 -j DROP

##################
## INPUT Lanac: ##
##################
$IPTABLES -A INPUT -p tcp -j bad_tcp_paketi
for i in $INET_IFACE $LAN_IFACE $WiFi_IFACE $LO_IFACE
do
  for j in $TCP_PORTS $D_TCP_PORTS $S_TCP_PORTS $I_TCP_PORTS
    do
      $IPTABLES -A INPUT -p TCP -m multiport -i $i --destination-port $j -j ACCEPT
  done
done

for i in $INET_IFACE $LAN_IFACE $WiFi_IFACE $LO_IFACE
do
  for j in $UDP_PORTS $D_UDP_PORTS $S_UDP_PORTS $I_UDP_PORTS
    do
      $IPTABLES -A INPUT -p UDP -m multiport -i $i --destination-port $j -j ACCEPT
  done
done

$IPTABLES -A INPUT -p ALL -i $LAN_IFACE -s $LAN_IP_RANGE -j ACCEPT
$IPTABLES -A INPUT -p ALL -i $WiFi_IFACE -s $WiFi_IP_RANGE -j ACCEPT
$IPTABLES -A INPUT -p ALL -i $LO_IFACE -s $LO_IP -j ACCEPT
$IPTABLES -A INPUT -p ALL -i $LO_IFACE -s $LAN_IP -j ACCEPT
$IPTABLES -A INPUT -p ALL -i $LO_IFACE -s $INET_IP -j ACCEPT
$IPTABLES -A INPUT -p ALL -i $LO_IFACE -s $WiFi_IP -j ACCEPT
$IPTABLES -A INPUT -p UDP -i $LAN_IFACE --dport 67 --sport 68 -j ACCEPT
$IPTABLES -A INPUT -p UDP -i $WiFi_IFACE --dport 67 --sport 68 -j ACCEPT
$IPTABLES -A INPUT -p ALL -d $INET_IP -m state --state ESTABLISHED,RELATED -j ACCEPT
$IPTABLES -A INPUT -p TCP -i $INET_IFACE -j tcp_paketi
$IPTABLES -A INPUT -p TCP -i $LAN_IFACE -j tcp_paketi
$IPTABLES -A INPUT -p TCP -i $WiFi_IFACE -j tcp_paketi
$IPTABLES -A INPUT -p UDP -i $INET_IFACE -j udp_paketi
$IPTABLES -A INPUT -p UDP -i $LAN_IFACE -j udp_paketi
$IPTABLES -A INPUT -p UDP -i $WiFi_IFACE -j udp_paketi
$IPTABLES -A INPUT -p ICMP -i $INET_IFACE -j icmp_paketi
$IPTABLES -A INPUT -p ICMP -i $LAN_IFACE -j icmp_paketi
$IPTABLES -A INPUT -p ICMP -i $WiFi_IFACE -j icmp_paketi
$IPTABLES -A INPUT -p ICMP -i $LO_IFACE -j icmp_paketi
$IPTABLES -A INPUT -p TCP -m multiport --destination-ports 63570:63750 -j ACCEPT # Opseg portova za Pasivni ftp
# Log-uj pakete koji se ne podudaraju sa prethodnim INPUT pravilima:
$IPTABLES -A INPUT -m limit --limit 3/minute --limit-burst 3 -j LOG --log-level DEBUG --log-prefix "INPUT paket umro:"

####################
## FORWARD Lanac: ##
####################
# Normalna posedavanja:
$IPTABLES -A FORWARD -p tcp -j bad_tcp_paketi
$IPTABLES -A FORWARD -i $LAN_IFACE -j ACCEPT
$IPTABLES -A FORWARD -i $WiFi_IFACE -j ACCEPT
$IPTABLES -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
# Moja specificna podesavanja za LAN_IFACE:
$IPTABLES -A FORWARD -i $INET_IFACE -o $LAN_IFACE -p TCP -m multiport --dport $D_TCP_PORTS -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT	# d00mil
$IPTABLES -A FORWARD -i $INET_IFACE -o $LAN_IFACE -p UDP -m multiport --dport $D_UDP_PORTS -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT	# d00mil

$IPTABLES -A FORWARD -i $INET_IFACE -o $LAN_IFACE -p TCP -m multiport --dport $S_TCP_PORTS -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT	# Srdjan
$IPTABLES -A FORWARD -i $INET_IFACE -o $LAN_IFACE -p UDP -m multiport --dport $S_UDP_PORTS -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT	# Srdjan

$IPTABLES -A FORWARD -i $INET_IFACE -o $WiFi_IFACE -p TCP -m multiport --dport $I_TCP_PORTS -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT	# IBM_ThinkPad
$IPTABLES -A FORWARD -i $INET_IFACE -o $WiFi_IFACE -p UDP -m multiport --dport $I_UDP_PORTS -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT	# IBM_ThinkPad

#$IPTABLES -A FORWARD -i $INET_IFACE -o $LAN_IFACE -p TCP --dport 3389 -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT	# Remote desktop
# Omoguci da se LAN i WiFi medjusobno vide
$IPTABLES -A FORWARD -i $LAN_IFACE -o $WiFi_IFACE -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
$IPTABLES -A FORWARD -i $WiFi_IFACE -o $LAN_IFACE -m state --state NEW,ESTABLISHED,RELATED -j ACCEPT
# Log-uj pakete koji se ne podudaraju sa prethodnim FORWARD pravilima:
$IPTABLES -A FORWARD -m limit --limit 3/minute --limit-burst 3 -j LOG --log-level DEBUG --log-prefix "FORWARD paket umro:"

###################
## OUTPUT Lanac: ##
###################
$IPTABLES -A OUTPUT -p tcp -j bad_tcp_paketi
$IPTABLES -A OUTPUT -p ALL -s $LO_IP -j ACCEPT
$IPTABLES -A OUTPUT -p ALL -s $LAN_IP -j ACCEPT
$IPTABLES -A OUTPUT -p ALL -s $WiFi_IP -j ACCEPT
$IPTABLES -A OUTPUT -p ALL -s $INET_IP -j ACCEPT
# Log-uj pakete koji se ne podudaraju sa prethodnim OUTPUT pravilima:
$IPTABLES -A OUTPUT -m limit --limit 3/minute --limit-burst 3 -j LOG --log-level DEBUG --log-prefix "OUTPUT paket umro:"

#####################################
## Jednostavan IP FORWARDING i NAT ##
#####################################
for i in `echo $D_TCP_PORTS | $TR , ' '`
do
$IPTABLES -A PREROUTING -t nat -p tcp -d $INET_IP --dport $i -m state --state NEW,ESTABLISHED,RELATED -j DNAT --to $D_IP:$i
done
for i in `echo $D_UDP_PORTS | $TR , ' '`
do
$IPTABLES -A PREROUTING -t nat -p udp -d $INET_IP --dport $i -m state --state NEW,ESTABLISHED,RELATED -j DNAT --to $D_IP:$i
done
for i in `echo $S_TCP_PORTS | $TR , ' '`
do
$IPTABLES -A PREROUTING -t nat -p tcp -d $INET_IP --dport $i -m state --state NEW,ESTABLISHED,RELATED -j DNAT --to $S_IP:$i
done
for i in `echo $S_UDP_PORTS | $TR , ' '`
do
$IPTABLES -A PREROUTING -t nat -p udp -d $INET_IP --dport $i -m state --state NEW,ESTABLISHED,RELATED -j DNAT --to $S_IP:$i
done
# Podesavanje da vise DC++ klijenata radi u isto vreme:
# d00mil
$IPTABLES -A PREROUTING -t nat -i $INET_IFACE -p tcp --dport 46411 -j DNAT --to $D_IP:46411
$IPTABLES -A PREROUTING -t nat -i $INET_IFACE -p udp --dport 46411 -j DNAT --to $D_IP:46411
$IPTABLES -A PREROUTING -t nat -d $INET_IP -p tcp --dport 46411 -m state --state NEW,ESTABLISHED,RELATED -j DNAT --to $D_IP:46411
$IPTABLES -A PREROUTING -t nat -d $INET_IP -p udp --dport 46411 -m state --state NEW,ESTABLISHED,RELATED -j DNAT --to $D_IP:46411
$IPTABLES -A PREROUTING -t nat -p tcp -d $INET_IP --dport 46411 -m state --state NEW,ESTABLISHED,RELATED -j DNAT --to $D_IP:46411
$IPTABLES -A PREROUTING -t nat -p udp -d $INET_IP --dport 46411 -m state --state NEW,ESTABLISHED,RELATED -j DNAT --to $D_IP:46411
# Srdjan
$IPTABLES -A PREROUTING -t nat -i $INET_IFACE -p tcp --dport 46511 -j DNAT --to $S_IP:46511
$IPTABLES -A PREROUTING -t nat -i $INET_IFACE -p udp --dport 46511 -j DNAT --to $S_IP:46511
$IPTABLES -A PREROUTING -t nat -d $INET_IP -p tcp --dport 46511 -m state --state NEW,ESTABLISHED,RELATED -j DNAT --to $S_IP:46511
$IPTABLES -A PREROUTING -t nat -d $INET_IP -p udp --dport 46511 -m state --state NEW,ESTABLISHED,RELATED -j DNAT --to $S_IP:46511
$IPTABLES -A PREROUTING -t nat -p tcp -d $INET_IP --dport 46511 -m state --state NEW,ESTABLISHED,RELATED -j DNAT --to $S_IP:46511
$IPTABLES -A PREROUTING -t nat -p udp -d $INET_IP --dport 46511 -m state --state NEW,ESTABLISHED,RELATED -j DNAT --to $S_IP:46511
# IBM_ThinkPad
$IPTABLES -A PREROUTING -t nat -p tcp -d $INET_IP --dport 46771 -m state --state NEW,ESTABLISHED,RELATED -j DNAT --to $I_IP:46771
$IPTABLES -A PREROUTING -t nat -p udp -d $INET_IP --dport 46771 -m state --state NEW,ESTABLISHED,RELATED -j DNAT --to $I_IP:46771
# OSTALO
$IPTABLES -A PREROUTING -t nat -p tcp -d $INET_IP --dport 3389 -m state --state NEW,ESTABLISHED,RELATED -j DNAT --to $D_IP:3389

#########################
## SNAT i MASQUERADING ##
#########################
$IPTABLES -A POSTROUTING -t nat -o $INET_IFACE -j SNAT --to $INET_IP

$IPTABLES -A POSTROUTING -t nat -d $D_IP -s $LAN_IP_RANGE -p tcp --dport 46411 -j SNAT --to $LO_IP
$IPTABLES -A POSTROUTING -t nat -d $D_IP -s $LAN_IP_RANGE -p udp --dport 46411 -j SNAT --to $LO_IP
$IPTABLES -A POSTROUTING -t nat -d $S_IP -s $LAN_IP_RANGE -p tcp --dport 46511 -j SNAT --to $LO_IP
$IPTABLES -A POSTROUTING -t nat -d $S_IP -s $LAN_IP_RANGE -p udp --dport 46511 -j SNAT --to $LO_IP

$IPTABLES -A POSTROUTING -t nat -d $WiFi_IP_RANGE -s $LAN_IP_RANGE -p tcp -j SNAT --to $LO_IP
$IPTABLES -A POSTROUTING -t nat -d $WiFi_IP_RANGE -s $LAN_IP_RANGE -p udp -j SNAT --to $LO_IP
$IPTABLES -A POSTROUTING -t nat -d $LAN_IP_RANGE -s $WiFi_IP_RANGE -p tcp -j SNAT --to $LO_IP
$IPTABLES -A POSTROUTING -t nat -d $LAN_IP_RANGE -s $WiFi_IP_RANGE -p udp -j SNAT --to $LO_IP
}

function stop_fn
{
for i in filter nat mangle
do
    $IPTABLES --table $i --flush
    $IPTABLES --table $i --delete-chain
done

$IPTABLES -F
$IPTABLES -P INPUT DROP
$IPTABLES -P OUTPUT DROP
$IPTABLES -P FORWARD DROP

$IPTABLES -t nat -A POSTROUTING -o $INET_IFACE -j SNAT --to $INET_IP
$IPTABLES -t nat -A POSTROUTING -o $INET_IFACE -j MASQUERADE
$IPTABLES -A FORWARD -i $INET_IFACE -j ACCEPT
}

TMP=${TMPDIR:-/tmp}/rc.firewall.tmp
trap "rm $TMP 2>/dev/null" 1

setup_fn
moduli_fn
hakeraj_fn

case "$1" in
  start)
  	if [ -e $TMP ]; then
		OLD_IP=$(< $TMP)
		if [ $OLD_IP != $INET_IP ]; then
			echo $INET_IP > $TMP
			/etc/rc.d/rc.netshaper stop
			stop_fn
			start_fn
			/etc/rc.d/rc.netshaper start
			echo `clock | awk ' { print $5 $6 } '` :: "Razlicite IP adrese $OLD_IP >>> $INET_IP, restartujem se"
		else
		        echo `clock | awk ' { print $5 $6 } '` :: "Iste IP adrese $OLD_IP >>> $INET_IP, izlazim"
		fi
	else
	        echo $INET_IP > $TMP
		start_fn
		/etc/rc.d/rc.netshaper start
		echo `clock | awk ' { print $5 $6 } '` :: "Skripta pokrenuta po prvi put u sesiji $OLD_IP >>> $INET_IP"
	fi
  	;;
  stop)
  	/etc/rc.d/rc.netshaper stop
  	stop_fn
	rm $TMP
  	;;
  info)
        info_fn
	;;
  *)
  	echo "Koriscenje: $0 (start|stop|info)"
  	exit 1
esac
