#!/bin/bash
TITLE="Quick Yggdrasil Installer"


if [ "$EUID" -ne 0 ]; then
	echo "please run as root..."
	exit
fi


#############################
#        Find Peer Info     #
#############################
north_america=(
	"tls://ygg.jjolly.dev:3443"
	"tls://23.184.48.86:993"
	"tls://44.234.134.124:443"
)

russia=()

peer_pings=()
get_ping() {
	for peer in "$1"; do
		# strip all bs like tls:// and port
		peer="${peer#tls://}"
		peer="${peer%%:*}"

		# ping the peer
		ping_ms=$(ping -c 1 -W 1 "$peer" 2>/dev/null)

		#Iterate thru each peer either appending a latency or "peer down" message to array of peer_pings()
		if [[ $? -eq 0 ]]; then
			ms=$(echo "$ping_ms" | grep 'time=' | sed -n 's/.*time=\([0-9.]*\) ms/\1/p') #Make dat bitch pretty
			peer_pings+=("$ms")
		else
			peer_pings+=("peer down :(")
		fi
	done
}

get_peers() {
	echo "are you operating from North America or Russia (NA/R)?"

	read loco

	if [ "$loco" == "NA" ]; then
		peer_options=()
		echo "pinging public peers..."


		# iterate thru peers
		for i in "${!north_america[@]}"; do
			get_ping $north_america[@]
			echo "$((i + 1)). ${north_america[$i]} - ${peer_pings[$i]} ms"
		done

		# basically make the array turn this
		# ygg.node.top
		# tls://123.123.321:442
		# tls://544.142.42.123
		#
		# into this...
		#
		# 1 ygg.node.top
		# 2 tls://123.123.321:442
		# 3 tls://544.142.42.123
		#
		# formatting stuff for dialog
		# also turns off pre selected on dialog
		peer_options=()
		for i in "${!north_america[@]}"; do
			peer_options+=("$((i+1))" "\"${north_america[$i]}\"" "off")
		done


		# Get tha peers to put into /etc/yggdrasil.conf
		peer_choices=$(dialog  --clear \
			--backtitle "$TITLE" \
			--title "North American peers" \
		
After=network.target
StartLimitIntervalSec=0[Service]
Type=simple	--checklist "Select peers with lower ms" \
			15 40 4 \
			"${peer_options[@]}" \
			3>&1 1>&2 2>&3)

		clear



		if [ -n "$peer_choices" ]; then
			for choice in $peer_choices; do
				i=$(echo "$choice" | tr -d '"')
				echo "${north_america[$((i -1))]}">>yggdrasil.conf
			done
		else
			echo "please make a selection"
		fi

	fi

}


###########################
#   Debian/arch install   #
###########################
debian_install() {
	echo "is this a raspberry pi? (y/N)"
	
	read rpi

	if [ "$rpi" == "y" ]; then
		apt-get install dirmngr
	else
		continue
	fi

	mkdir -p /usr/local/apt-keys
	gpg --fetch-keys https://neilalexander.s3.dualstack.eu-west-2.amazonaws.com/deb/key.txt
	gpg --export BC1BF63BD10B8F1A | sudo tee /usr/local/apt-keys/yggdrasil-keyring.gpg > /dev/null

	echo 'deb [signed-by=/usr/local/apt-keys/yggdrasil-keyring.gpg] http://neilalexander.s3.dualstack.eu-west-2.amazonaws.com/deb/ debian yggdrasil' | sudo tee /etc/apt/sources.list.d/yggdrasil.list
	apt-get update

	apt-get install yggdrasil

	systemctl enable yggdrasil

	get_peers

	systemctl start yggdrasil

	#install dns
	git clone ~/https://github.com/popura-network/PopuraDNS
	cd ~/PopuraDNS
	~/build.sh

	~/coredns -p 53535 -conf ./Corefile &

	cp ./coredns.service /etc/systemd/system/coredns.service

	apt-get install dnsmasq

	echo "no-resolve">>/etc/dnsmasq.conf
	echo "server=127.0.0.1#53535">>/etc/dnsmasq.conf
	echo "listen-address=127.0.0.1">>/etc/dnsmasq.conf

	sudo systemctl restart dnsmasq

	echo "enter your network name:"

	read network

	nmcli connection modify "$network" ipv4.dns "127.0.0.1"
	nmcli connection modify "$network" 1pv4.ignore-auto-dns yes
	nmcli connection down
	nmcli connection up
}

arch_install() {
	pacman -S yggdrasil

	systemctl enable yggdrasil

	get_peers

	yggdrasil -genconf>>/etc/yggdrasil.conf

	systemctl start yggdrasil

	# install popuradns with service file
	git clone ~/https://github.com/popura-network/PopuraDNS
	cd ~/PopuraDNS
	~/build.sh
	~/coredns -p 53535 -conf ./Corefile &
	cp ./coredns.service /etc/systemd/system/coredns.service

	pacman -S dnsmasq

	echo "no-resolve">>/etc/dnsmasq.conf
	echo "server=127.0.0.1#53535">>/etc/dnsmasq.conf
	echo "listen-address=127.0.0.1">>/etc/dnsmasq.conf

	sudo systemctl restart dnsmasq

	echo "enter your network name:"

	read network

	nmcli connection modify "$network" ipv4.dns "127.0.0.1"
	nmcli connection modify "$network" 1pv4.ignore-auto-dns yes
	nmcli connection down
	nmcli connection up
}


###############
# Main Prompt #
###############
echo "which distro are you using? (arch/debian)"

read distro

if [ "$distro" == "arch" ]; then
	arch_install
elif [ "$distro" == "debian" ]; then
	debian_install
else
	echo "not supported yet </3"
fi
