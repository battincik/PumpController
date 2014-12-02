#!/bin/bash

promptUser() {
	while :
	do
		read -p "$1 (y|Y|n|N)?" resp
		case "$resp" in
			y|Y ) return;;
			n|N ) exit 0;;
			* ) echo "try Y|y|N|n";;
		esac
	done
}

#parse input
if (( $# < 1 || $# > 2 )); then
	echo "Wrong number of arguments"
	echo "Try $0 [server|pumpcontroller]"
	exit 0
fi
if [[ $1 == "server" ]]; then
	server=1
elif [[ $1 == "pumpcontroller" ]]; then
	pc=1
else
	echo "Undefined argument \"$1\"!"
	echo "Try $0 [server|pumpcontroller]"
	exit 0
fi
if (( $# == 2 )); then
	if [[ $2 == "fast" ]]; then
		cpanmSwitch="--notest"
	else
		echo "Undefined argument \"$2\"!"
		echo "Try $0 [server|pumpcontroller] [fast]"
		exit 0
	fi
fi

if [[ $server ]]; then
	echo "Success server"
fi
if [[ $pc ]]; then
	echo "Success pumpcontroller"
fi

sudo apt-get update

#Make this smarter. Check to see what's necessary and then do it..
echo "Installing gcc"
sudo apt-get install gcc
promptUser "Continue"

ret=$(which 'cc')
if [ -z "$ret" ]; then
	sudo ln -s /usr/bin/gcc /etc/alternatives/cc
	sudo ln -s /etc/alternatives/cc /usr/bin/cc
fi

echo "Installing Perl:"
sudo apt-get install perl

echo "Installing some utilities:"
sudo apt-get install makepatch
promptUser "Continue"
sudo apt-get install sendmail
promptUser "Continue"
sudo apt-get install git
promptUser "Continue"
sudo apt-get install curl
promptUser "Continue"

echo "Installing Perlbrew:"
curl -L http://install.perlbrew.pl | bash
echo 'source ~/perl5/perlbrew/etc/bashrc' >> $HOME/.bashrc
source ~/perl5/perlbrew/etc/bashrc
perlbrew install-cpanm
echo "Installing perl-5.16.3 locally:"
perlbrew install perl-5.16.3
source ~/perl5/perlbrew/etc/bashrc
perlbrew switch perl-5.16.3
str=$(which perl | grep $HOME | grep '5.16.3')
if [[ -z "$str" ]]; then
	echo "Perlbrew setup didn't work properly, exiting."
	exit -1;
fi
echo "Seems like the Perlbrew environment is set-up properly."
promptUser "Continue"

if [[ $server ]]; then
	echo "Installing Nginx:"
	sudo apt-get install nginx
	promptUser "Continue"
fi

if [[ $pc ]]; then
	echo "Installing Curses:"
	sudo apt-get install libncurses5-dev
	promptUser "Continue"
fi

echo "Installing CouchDB:"
sudo apt-get install couchdb
promptUser "Continue"

echo "Installing python tool to dump and restore couch content:"
sudo apt-get install python-couchdb
promptUser "Continue"

if [[ $server ]]; then
	#LWP::Protocol::https needs Net::SSLeay which needs openssl headers
	#It does caution that the openssl should be compiled with the same compiler
	#as is compiling Net::SSLeay. But this seems to work fine at this point in time!
	echo "Installing libssl-dev:"
	sudo apt-get install libssl-dev
	promptUser "Continue"
fi
#This is not necessary with cpanm and perlbrew..
#if [[ $server ]]; then
#	echo "Installing dancer library:"
#	sudo apt-get install libdancer-perl
#	promptUser "Continue"
#fi

# echo "install daemontools for svc:"
# sudo apt-get install daemontools
echo "Installing upstart for upstart:"
sudo apt-get install upstart
promptUser "Continue"

#This is done inside perlbrew now
#echo "Installing CPANMinus:"
#curl -L http://cpanmin.us | perl - --sudo App::cpanminus
#promptUser "Continue"

echo "Installing required perl modules using CPANM -- these really should just go, seriously:|"
cpanm --skip-installed --verbose $cpanmSwitch Math::Round Test::More YAML DateTime Try::Tiny Time::HiRes Moose methods Curses #Device::SerialPort Control::CLI
if [[ $server ]]; then
	cpanm --skip-installed --verbose $cpanmSwitch Dancer~1.3051 Data::UUID Email::Date::Format Email::Valid LWP::Protocol::https Number::Phone URI::Query Template Digest::SHA1 Module::Refresh HTML::Strip
	promptUser "Continue"
	echo "Installing required perl modules using CPANM -- these produced some grief before..:"
	cpanm --skip-installed --verbose $cpanmSwitch Dancer::Plugin::Email Dancer::Plugin::Bcrypt Dancer::Plugin::Auth::RBAC
fi
promptUser "Continue"

echo "Installing required perl modules using CPANM ... contd. This one module AnyEvent::CouchDB is known to fail its standards tests because of an syntax error in the test code. Running CPANM with force flag:"
cpanm --skip-installed --verbose $cpanmSwitch JSON::XS PadWalker Async::Interrupt
cpanm --skip-installed --force --verbose $cpanmSwitch Switch CouchDB::View
cpanm --skip-installed --verbose $cpanmSwitch AnyEvent::CouchDB 
promptUser "Continue"

if [[ $server ]]; then
	echo "Tests were failing, could not figure out why"
	cpanm --skip-installed --verbose --force $cpanmSwitch Dancer::Session::Cookie Plack Starman
	promptUser "Continue"
fi

echo "Installing some utility perl modules for debugging:"
cpanm --skip-installed $cpanmSwitch Data::Dumper
promptUser "Continue"

#Rolled out own driver. Don't think we need these anymore.
#echo "Low level libraries"
#mkdir insTmp
#cd insTmp
#wget 'http://www.airspayce.com/mikem/bcm2835/bcm2835-1.25.tar.gz'
#tar zxvf bcm2835-1.25.tar.gz
#cd bcm2835-1.25
#./configure
#make
#sudo make check
#sudo make install
#cd ../../
#rm -rf insTmp

#cpanm --skip-installed --verbose Device::BCM2835
#promptUser "Continue"

if [[ $pc ]]; then

	sudo apt-get install python-dev
	cpanm --skip-installed --verbose $cpanmSwitch Path::Class Parse::RecDescent Inline::Python
	#this needs reboot
	cp /etc/modules ./modules.tmp

	echo 'i2c-bcm2708' >> ./modules.tmp #grep for stuff first
	cp /etc/modprobe.d/raspi-blacklist.conf ./blacklist.tmp
	sed -i 's/^blacklist i2c-bcm2708$/#blacklist i2c-bcm2708/' ./blacklist.tmp
	sudo mv ./blacklist.tmp /etc/modprobe.d/raspi-blacklist.conf

	echo 'i2c-dev' >> ./modules.tmp
	sudo mv ./modules.tmp /etc/modules
	sudo apt-get install python-smbus

	#enable spi for the piface interface board
	cp /etc/modprobe.d/raspi-blacklist.conf ./blacklist.tmp
	sed -i 's/^blacklist spi-bcm2708$/#blacklist spi-bcm2708/' ./blacklist.tmp
	sudo mv ./blacklist.tmp /etc/modprobe.d/raspi-blacklist.conf
	promptUser "Continue"

	#sudo useradd -r -s /bin/false biopay
	#sudo usermod -G www-data -a saamaan
	#sudo usermod -G www-data -a biopay
	#sudo usermod -G biopay -a saamaan
	#promptUser "Continue"
	#
	##These should probably be done through sudo su www-data and biopay 
	##instead of all these chowns and chmods!
	#sudo mkdir /var/www/
	#sudo chown root:www-data /var/www
	#sudo chmod 775 /var/www
	#promptUser "Continue"
	#
	#sudo mkdir /var/www/biopay
	#sudo chown -R root:biopay /var/www/biopay
	#sudo chmod -R 775 /var/www/biopay
	#promptUser "Continue"
	#
	#sudo mkdir /var/log/biopay
	#sudo chown -R root:biopay /var/log/biopay
	#sudo chmod -R 775 /var/log/biopay
	#sudo touch /var/log/biopay/biopay-web.log
	#sudo chown root:biopay /var/log/biopay/biopay-web.log
	#promptUser "Continue"
	#
	#sudo touch /var/log/nginx/biopay-error.log
	#sudo touch /var/log/nginx/biopay-access.log
	#sudo chown www-data:root biopay-error.log biopay-access.log
	#sudo chmod 660 biopay-error.log biopay-access.log
	#promptUser "Continue"
	#
	#perl Makefile.PL
	#promptUser "Continue"
	#
	#make
	#promptUser "Continue"
	#
	#make test
	#promptUser "Continue"
	#
	#sudo make install
	#promptUser "Continue"
fi

#Make sure all perl modules are installed properly 
moduleList=$(perlbrew list-modules)
reqModules=( Math::Round Test::More YAML DateTime Try::Tiny Time::HiRes Moose methods Switch JSON::XS PadWalker Async::Interrupt CouchDB::View AnyEvent::CouchDB Data::Dumper )
if [[ $pc ]]; then
	reqModules+=( Parse::RecDescent Inline::Python )
fi
if [[ $server ]]; then
	reqModules+=( Dancer~1.3051 Data::UUID Email::Date::Format Email::Valid LWP::Protocol::https Number::Phone URI::Query Template Digest::SHA1 Module::Refresh HTML::Strip Dancer::Plugin::Email Dancer::Plugin::Bcrypt Dancer::Plugin::Auth::RBAC Dancer::Session::Cookie Plack Starman )
fi

for m in ${reqModules[@]}; do
	res=$(echo $moduleList | grep $m)
	if [[ -z "$res" ]]; then
		echo "$m module is missing"
	fi
done
