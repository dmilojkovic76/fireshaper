#!/bin/sh
# Use !/bin/sh -x instead if you want to know what the script does.
#-----------------------------------------------------------------------------
#  /etc/rc.d/rc.netshaper
# verzija 0.20 15.09.2007
# Skripta za podesavanje Rutiranja Interneta
# Prvi put napisana 02.03.2007.
#
# d00mil.d00mil@gmail.com
#-----------------------------------------------------------------------------
#

function configure_fn
{
# === Promenljive i default vrednosti ===

# Konfiguracijski faj po defaultul:
DEF_CONFIG="/etc/netshaper.config"
USER_CONFIG=0

# Putanje do programa
MODPROBE=`which modprobe`
IPTABLES=`which iptables`
IFCONFIG=`which ifconfig`
IWCONFIG=`which iwconfig`
TC=`which tc`
GREP=`which grep`
SED=`which sed`

# Internet parametri:
INET_IFACE="ppp0" # Internet adapter
DOWNLINK="1024" # Brzina zakupljene konekcije
UPLINK="128" # Brzina zakupljene konekcije
DOWNRATE_UMANJ_PROC=5 # Globalno procentualno umanjenje
DOWNRATE_UMANJ_USER_PROC=5 # Procentualno umanjenje po korisniku
UPRATE_UMANJ_PROC=5 # Globalno procentualno umanjenje
UPRATE_UMANJ_USER_PROC=5 # Procentualno umanjenje po korisniku

# LAN Parametri:
LAN_IFACE=eth0
}
#printf "\033[40m\033[1;34m=============================================================================\033[0m\n"
#printf "\033[40m\033[1;34m          d00mil's IPTables NetShaper Script $verzija\033[0m\n"
#printf "\033[40m\033[1;34m=============================================================================\033[0m\n"
#echo

function start_fn {
################## S T A R T ##################################################
# Ucitavanje potrebnih modula:
/sbin/depmod -a
# potrebni moduli za IMQ (Intermediate Queuing Devices):
if ! lsmod | grep -q imq; then
    /sbin/modprobe imq numdevs=2
fi
if ! lsmod | grep -q ipt_IMQ; then
    /sbin/modprobe ipt_IMQ
fi

# Ovo je uradjeno i u /etc/ppp/pppoe.conf
$IPTABLES -A FORWARD -o ppp0 -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu

################# Q O S #########################################################
tc qdisc del dev imq0 root 2> /dev/null
tc qdisc del dev imq1 root 2> /dev/null

ip link set imq0 down
ip link set imq1 down

ip link set dev imq0 qlen 30
ip link set dev imq0 mtu 1400

ip link set dev imq1 qlen 30
ip link set dev imq1 mtu 1400
###############################################
# Traffic shaping
###############################################

# Interfaceovi - imq0 za upload, imq1 za download:
IFACE_UP=imq0
IFACE_DN=imq1

# Prioriteti
MARKPRIO1="1" # Interactive - tipa ack, icmp, ssh
MARKPRIO2="2" # Misc - ono sto ne spada nigde i mesindzeri
MARKPRIO3="3" # Browsing - http, smtp...
MARKPRIO4="4" # P2P

# Bandwith i klasifikacije bandwitha za prioritete
let DOWNRATE=($[$DOWNLINK*90/100]) # Ukupni Download je 90% brzine down-linka
let UPRATE=($[$UPLINK*80/100]) # Ukupni Upload je 71% brzine up-linka sto je oko 90kbps

## P2PRATE je max rate za P2P
##
## UP-limiti :
let P2PRATE=($[$UPRATE*8/10])
let PRIORATE1=($[$UPRATE/3])
let PRIORATE2=($[$UPRATE/4])
let PRIORATE3=($[$UPRATE/4])
let PRIORATE4=($[$UPRATE/7])

## DOWN-limiti :
let P2PRATE2=($[$DOWNRATE*8/10])
let PRIORATE5=($[$DOWNRATE/3])
let PRIORATE6=($[$DOWNRATE/4])
let PRIORATE7=($[$DOWNRATE/4])
let PRIORATE8=($[$DOWNRATE/7])

# Quantums - vidi http://gentoo-wiki.com/HOWTO_Packet_Shaping
# Quantumi odredjuju kako se bandwidth deli medju qdisc-ovima
QUANTUM1="12187"
QUANTUM2="8625"
QUANTUM3="5062"
QUANTUM4="1500"

# Burst - dozvoljena prekoracenja po klasama
### UPLOAD
let BURSTU=($[$UPRATE/32])
### DOWNLOAD
let BURSTD=($[$DOWNRATE/32])

### UPLOAD CBURST
let CBURSTU=($[$UPRATE/32])
### DOWNLOAD CBURST
let CBURSTD=($[$DOWNRATE/32])

#echo "   - Bandwidth: $[$DOWNRATE/8] KB/s / $[$UPRATE/8] KB/s"
echo "   - Ukupan P2P Upload ogranicen na: $P2PRATE kbps ($[$P2PRATE/8] KB/s)"
echo "   - Ukupan P2P Download ogranicen na: $P2PRATE2 kbps ($[$P2PRATE2/8] KB/s)"
#echo "   - Upload ogranicen na 4 klase:  $[$PRIORATE1/8] KB/s, $[$PRIORATE2/8] KB/s, $[$PRIORATE3/8] KB/s, $[$PRIORATE4/8] KB/s"
#echo "   - Download ogranicen na 4 klase: $[$PRIORATE5/8] KB/s, $[$PRIORATE6/8] KB/s, $[$PRIORATE7/8] KB/s, $[$PRIORATE8/8] KB/s"


################# Kraj osnovnih podesavanja qos-a #######################
ip link set imq0 up
ip link set imq1 up

# PODESAVANJA ZA IMQ0 - UPLOAD
tc qdisc add dev $IFACE_UP root handle 1: htb default 103

# root class:
tc class add dev $IFACE_UP parent 1: classid 1:1 htb rate ${UPRATE}kbit burst ${BURSTU}kbit cburst ${CBURSTU}kbit
# sub classes:
tc class add dev $IFACE_UP parent 1:1 classid 1:101 htb rate ${PRIORATE1}kbit ceil ${UPRATE}kbit quantum $QUANTUM1 burst ${BURSTU}kbit cburst ${CBURSTU}kbit prio 0
tc class add dev $IFACE_UP parent 1:1 classid 1:102 htb rate ${PRIORATE2}kbit ceil ${UPRATE}kbit quantum $QUANTUM2 burst ${BURSTU}kbit cburst ${CBURSTU}kbit prio 1
tc class add dev $IFACE_UP parent 1:1 classid 1:103 htb rate ${PRIORATE3}kbit ceil ${UPRATE}kbit quantum $QUANTUM3 burst ${BURSTU}kbit cburst ${CBURSTU}kbit prio 2
tc class add dev $IFACE_UP parent 1:1 classid 1:104 htb rate ${PRIORATE4}kbit ceil ${P2PRATE}kbit quantum $QUANTUM4 burst ${BURSTU}kbit cburst ${CBURSTU}kbit prio 3
# filter packets:
tc filter add dev $IFACE_UP parent 1:0 protocol ip prio 0 handle $MARKPRIO1 fw classid 1:101
tc filter add dev $IFACE_UP parent 1:0 protocol ip prio 1 handle $MARKPRIO2 fw classid 1:102
tc filter add dev $IFACE_UP parent 1:0 protocol ip prio 2 handle $MARKPRIO3 fw classid 1:103
tc filter add dev $IFACE_UP parent 1:0 protocol ip prio 3 handle $MARKPRIO4 fw classid 1:104
# queuing disciplines:
tc qdisc add dev $IFACE_UP parent 1:101 sfq perturb 10 quantum $QUANTUM1
tc qdisc add dev $IFACE_UP parent 1:102 sfq perturb 10 quantum $QUANTUM2
tc qdisc add dev $IFACE_UP parent 1:103 sfq perturb 10 quantum $QUANTUM3
tc qdisc add dev $IFACE_UP parent 1:104 sfq perturb 10 quantum $QUANTUM4
### Kraj podesavanja za upload ###

# PODESAVANJA ZA IMQ1 - DOWNLOAD
tc qdisc add dev $IFACE_DN root handle 1: htb default 103

# root class:
tc class add dev $IFACE_DN parent 1: classid 1:1 htb rate ${DOWNRATE}kbit burst ${BURSTD}kbit cburst ${CBURSTD}kbit
# sub classes:
tc class add dev $IFACE_DN parent 1:1 classid 1:101 htb rate ${PRIORATE5}kbit ceil ${DOWNRATE}kbit quantum $QUANTUM1 burst ${BURSTD}kbit cburst ${CBURSTD}kbit prio 0
tc class add dev $IFACE_DN parent 1:1 classid 1:102 htb rate ${PRIORATE6}kbit ceil ${DOWNRATE}kbit quantum $QUANTUM2 burst ${BURSTD}kbit cburst ${CBURSTD}kbit prio 1
tc class add dev $IFACE_DN parent 1:1 classid 1:103 htb rate ${PRIORATE7}kbit ceil ${DOWNRATE}kbit quantum $QUANTUM3 burst ${BURSTD}kbit cburst ${CBURSTD}kbit prio 2
tc class add dev $IFACE_DN parent 1:1 classid 1:104 htb rate ${PRIORATE8}kbit ceil ${P2PRATE2}kbit quantum $QUANTUM4 burst ${BURSTD}kbit cburst ${CBURSTD}kbit prio 3
# filters packets:
tc filter add dev $IFACE_DN parent 1:0 protocol ip prio 0 handle $MARKPRIO1 fw classid 1:101
tc filter add dev $IFACE_DN parent 1:0 protocol ip prio 1 handle $MARKPRIO2 fw classid 1:102
tc filter add dev $IFACE_DN parent 1:0 protocol ip prio 2 handle $MARKPRIO3 fw classid 1:103
tc filter add dev $IFACE_DN parent 1:0 protocol ip prio 3 handle $MARKPRIO4 fw classid 1:104
# queuing disciplines:
tc qdisc add dev $IFACE_DN parent 1:101 sfq perturb 10 quantum $QUANTUM1
tc qdisc add dev $IFACE_DN parent 1:102 sfq perturb 10 quantum $QUANTUM2
tc qdisc add dev $IFACE_DN parent 1:103 sfq perturb 10 quantum $QUANTUM3
tc qdisc add dev $IFACE_DN parent 1:104 sfq perturb 10 quantum $QUANTUM4
### Kraj podesavanja za download ###

### Kreiranje novih lanaca u mangle tabeli za klasifikaciju paketa ###
$IPTABLES -t mangle -N adsl-out
$IPTABLES -t mangle -N adsl-in

### Layer 7 filteri za upload
$IPTABLES -t mangle -A adsl-out -p tcp --syn -j MARK --set-mark $MARKPRIO1
$IPTABLES -t mangle -A adsl-out -p icmp -j MARK --set-mark $MARKPRIO1
$IPTABLES -t mangle -A adsl-out -m layer7 --l7proto dns -j MARK --set-mark $MARKPRIO1
$IPTABLES -t mangle -A adsl-out -m layer7 --l7proto sip -j MARK --set-mark $MARKPRIO1
$IPTABLES -t mangle -A adsl-out -m layer7 --l7proto rdp -j MARK --set-mark $MARKPRIO1
$IPTABLES -t mangle -A adsl-out -m layer7 --l7proto vnc -j MARK --set-mark $MARKPRIO1
$IPTABLES -t mangle -A adsl-out -m layer7 --l7proto exe -j MARK --set-mark $MARKPRIO3
$IPTABLES -t mangle -A adsl-out -m layer7 --l7proto flash -j MARK --set-mark $MARKPRIO3
$IPTABLES -t mangle -A adsl-out -m layer7 --l7proto ogg -j MARK --set-mark $MARKPRIO3
$IPTABLES -t mangle -A adsl-out -m layer7 --l7proto pdf -j MARK --set-mark $MARKPRIO3
$IPTABLES -t mangle -A adsl-out -m layer7 --l7proto rar -j MARK --set-mark $MARKPRIO3
$IPTABLES -t mangle -A adsl-out -m layer7 --l7proto tar -j MARK --set-mark $MARKPRIO3
$IPTABLES -t mangle -A adsl-out -m layer7 --l7proto zip -j MARK --set-mark $MARKPRIO3
$IPTABLES -t mangle -A adsl-out -m layer7 --l7proto validcertssl -j MARK --set-mark $MARKPRIO1
$IPTABLES -t mangle -A adsl-out -m layer7 --l7proto ftp -j MARK --set-mark $MARKPRIO3
$IPTABLES -t mangle -A adsl-out -m layer7 --l7proto http -j MARK --set-mark $MARKPRIO2
$IPTABLES -t mangle -A adsl-out -m layer7 --l7proto imap -j MARK --set-mark $MARKPRIO2
$IPTABLES -t mangle -A adsl-out -m layer7 --l7proto nntp -j MARK --set-mark $MARKPRIO2
$IPTABLES -t mangle -A adsl-out -m layer7 --l7proto pop3 -j MARK --set-mark $MARKPRIO2
$IPTABLES -t mangle -A adsl-out -m layer7 --l7proto smtp -j MARK --set-mark $MARKPRIO2
$IPTABLES -t mangle -A adsl-out -m layer7 --l7proto ssh -j MARK --set-mark $MARKPRIO1
$IPTABLES -t mangle -A adsl-out -m layer7 --l7proto smb -j MARK --set-mark $MARKPRIO3
$IPTABLES -t mangle -A adsl-out -m layer7 --l7proto irc -j MARK --set-mark $MARKPRIO3
$IPTABLES -t mangle -A adsl-out -m layer7 --l7proto aim -j MARK --set-mark $MARKPRIO3
$IPTABLES -t mangle -A adsl-out -m layer7 --l7proto msnmessenger -j MARK --set-mark $MARKPRIO2
$IPTABLES -t mangle -A adsl-out -m layer7 --l7proto skypeout -j MARK --set-mark $MARKPRIO2
$IPTABLES -t mangle -A adsl-out -m layer7 --l7proto skypetoskype -j MARK --set-mark $MARKPRIO2
$IPTABLES -t mangle -A adsl-out -m layer7 --l7proto msn-filetransfer -j MARK --set-mark $MARKPRIO3
$IPTABLES -t mangle -A adsl-out -m layer7 --l7proto jabber -j MARK --set-mark $MARKPRIO2
$IPTABLES -t mangle -A adsl-out -m layer7 --l7proto bittorrent -j MARK --set-mark $MARKPRIO4
$IPTABLES -t mangle -A adsl-out -m layer7 --l7proto directconnect -j MARK --set-mark $MARKPRIO4
$IPTABLES -t mangle -A adsl-out -m layer7 --l7proto edonkey -j MARK --set-mark $MARKPRIO4
$IPTABLES -t mangle -A adsl-out -m layer7 --l7proto fasttrack -j MARK --set-mark $MARKPRIO4
$IPTABLES -t mangle -A adsl-out -m layer7 --l7proto gnutella -j MARK --set-mark $MARKPRIO4
$IPTABLES -t mangle -A adsl-out -m layer7 --l7proto tesla -j MARK --set-mark $MARKPRIO3
$IPTABLES -t mangle -A adsl-out -m layer7 --l7proto unknown -j MARK --set-mark $MARKPRIO4
$IPTABLES -t mangle -A adsl-out -m layer7 --l7proto ntp -j MARK --set-mark $MARKPRIO2
$IPTABLES -t mangle -A adsl-out -m mark --mark 0 -j MARK --set-mark $MARKPRIO3
### Pa za download ############
$IPTABLES -t mangle -A adsl-in -p icmp -j MARK --set-mark $MARKPRIO1
$IPTABLES -t mangle -A adsl-in -m layer7 --l7proto dns -j MARK --set-mark $MARKPRIO1
$IPTABLES -t mangle -A adsl-in -m layer7 --l7proto sip -j MARK --set-mark $MARKPRIO1
$IPTABLES -t mangle -A adsl-in -m layer7 --l7proto rdp -j MARK --set-mark $MARKPRIO1
$IPTABLES -t mangle -A adsl-in -m layer7 --l7proto vnc -j MARK --set-mark $MARKPRIO1
$IPTABLES -t mangle -A adsl-in -m layer7 --l7proto exe -j MARK --set-mark $MARKPRIO3
$IPTABLES -t mangle -A adsl-in -m layer7 --l7proto flash -j MARK --set-mark $MARKPRIO3
$IPTABLES -t mangle -A adsl-in -m layer7 --l7proto ogg -j MARK --set-mark $MARKPRIO3
$IPTABLES -t mangle -A adsl-in -m layer7 --l7proto pdf -j MARK --set-mark $MARKPRIO3
$IPTABLES -t mangle -A adsl-in -m layer7 --l7proto rar -j MARK --set-mark $MARKPRIO3
$IPTABLES -t mangle -A adsl-in -m layer7 --l7proto tar -j MARK --set-mark $MARKPRIO3
$IPTABLES -t mangle -A adsl-in -m layer7 --l7proto zip -j MARK --set-mark $MARKPRIO3
$IPTABLES -t mangle -A adsl-in -m layer7 --l7proto validcertssl -j MARK --set-mark $MARKPRIO1
$IPTABLES -t mangle -A adsl-in -m layer7 --l7proto ftp -j MARK --set-mark $MARKPRIO3
$IPTABLES -t mangle -A adsl-in -m layer7 --l7proto http -j MARK --set-mark $MARKPRIO2
$IPTABLES -t mangle -A adsl-in -m layer7 --l7proto imap -j MARK --set-mark $MARKPRIO2
$IPTABLES -t mangle -A adsl-in -m layer7 --l7proto nntp -j MARK --set-mark $MARKPRIO2
$IPTABLES -t mangle -A adsl-in -m layer7 --l7proto pop3 -j MARK --set-mark $MARKPRIO2
$IPTABLES -t mangle -A adsl-in -m layer7 --l7proto smtp -j MARK --set-mark $MARKPRIO2
$IPTABLES -t mangle -A adsl-in -m layer7 --l7proto ssh -j MARK --set-mark $MARKPRIO1
$IPTABLES -t mangle -A adsl-in -m layer7 --l7proto smb -j MARK --set-mark $MARKPRIO1
$IPTABLES -t mangle -A adsl-in -m layer7 --l7proto irc -j MARK --set-mark $MARKPRIO3
$IPTABLES -t mangle -A adsl-in -m layer7 --l7proto aim -j MARK --set-mark $MARKPRIO3
$IPTABLES -t mangle -A adsl-in -m layer7 --l7proto msnmessenger -j MARK --set-mark $MARKPRIO2
$IPTABLES -t mangle -A adsl-in -m layer7 --l7proto skypeout -j MARK --set-mark $MARKPRIO2
$IPTABLES -t mangle -A adsl-in -m layer7 --l7proto skypetoskype -j MARK --set-mark $MARKPRIO2
$IPTABLES -t mangle -A adsl-in -m layer7 --l7proto msn-filetransfer -j MARK --set-mark $MARKPRIO3
$IPTABLES -t mangle -A adsl-in -m layer7 --l7proto jabber -j MARK --set-mark $MARKPRIO2
$IPTABLES -t mangle -A adsl-in -m layer7 --l7proto bittorrent -j MARK --set-mark $MARKPRIO4
$IPTABLES -t mangle -A adsl-in -m layer7 --l7proto directconnect -j MARK --set-mark $MARKPRIO4
$IPTABLES -t mangle -A adsl-in -m layer7 --l7proto edonkey -j MARK --set-mark $MARKPRIO4
$IPTABLES -t mangle -A adsl-in -m layer7 --l7proto fasttrack -j MARK --set-mark $MARKPRIO4
$IPTABLES -t mangle -A adsl-in -m layer7 --l7proto gnutella -j MARK --set-mark $MARKPRIO4
$IPTABLES -t mangle -A adsl-in -m layer7 --l7proto tesla -j MARK --set-mark $MARKPRIO3
$IPTABLES -t mangle -A adsl-in -m layer7 --l7proto unknown -j MARK --set-mark $MARKPRIO3
$IPTABLES -t mangle -A adsl-in -m layer7 --l7proto ntp -j MARK --set-mark $MARKPRIO2
$IPTABLES -t mangle -A adsl-in -m mark --mark 0 -j MARK --set-mark $MARKPRIO3

### Klasifikacija po gornjim pravilima ###
$IPTABLES -t mangle -A PREROUTING -p tcp --sport telnet -j TOS --set-tos Minimize-Delay
$IPTABLES -t mangle -A PREROUTING -p tcp --sport ftp -j TOS --set-tos Minimize-Delay
$IPTABLES -t mangle -A PREROUTING -p tcp --sport ftp-data -j TOS --set-tos Maximize-Throughput
$IPTABLES -t mangle -A PREROUTING -i $INET_IFACE -j adsl-in
$IPTABLES -t mangle -A POSTROUTING -o $INET_IFACE -j adsl-out
$IPTABLES -t mangle -A INPUT -i $INET_IFACE -j adsl-in
$IPTABLES -t mangle -A OUTPUT -o $INET_IFACE -j adsl-out

## Preusmeravanje paketa IMQ device-ovima ###
$IPTABLES -t mangle -A adsl-in -j IMQ --todev 1
$IPTABLES -t mangle -A adsl-out -j IMQ --todev 0
}

function stop_fn {
tc qdisc del dev imq0 root 2> /dev/null
tc qdisc del dev imq1 root 2> /dev/null

ip link set imq0 down
ip link set imq1 down

$IPTABLES --table mangle --flush
$IPTABLES --table mangle --delete-chain
}

configure_fn

case "$1" in
  start)
	start_fn
	echo `clock | awk ' { print $5 $6 } '` :: rc.netshaper pokrenut
	;;
  stop)
	stop_fn
	echo `clock | awk ' { print $5 $6 } '` :: rc.netshaper zaustavljen
	;;
  restart)
	stop_fn
	sleep 3
	start_fn
	echo `clock | awk ' { print $5 $6 } '` :: rc.netshaper ponovo pokrenut
	;;
  *)
	echo "Koriscenje: $0 (start|stop|restart)"
	exit 1
esac

