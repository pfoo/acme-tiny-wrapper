#! /bin/bash

#v1.1

#You might need to change this if acme-tiny switch from github or if letsencrypt change their intermediate certificate
acme_tiny_url="https://raw.githubusercontent.com/diafygi/acme-tiny/master/acme_tiny.py"
le_intermediate_url="https://acme-v01.api.letsencrypt.org/acme/issuer-cert"

#########################
# don't edit below here #
#########################

#Define this script path
my_source="${BASH_SOURCE[0]}"
while [ -h "$my_source" ]; do # resolve $my_source until the file is no longer a symlink
  my_dir="$( cd -P "$( dirname "$my_source" )" && pwd )"
  my_source="$(readlink "$my_source")"
  [[ $my_source != /* ]] && my_source="$my_dir/$my_source" # if $my_source was a relative symlink, need to resolve its relative to the path where the symlink file was located
done
my_dir="$( cd -P "$( dirname "$my_source" )" && pwd )/"

#init default values
declare acme_user=""
declare -u account_key_type="RSA"
declare -u domain_key_type="RSA"
declare -l use_custom_dh="no"
declare -l use_custom_ecdh=""
declare -l renew_domain_key="no"

#loading default configuration file
if [ -f $my_dir/config.cf ]; then
        source $my_dir/config.cf
fi

#######################################################
################### OPTION HANDLING ###################
#######################################################

#check if GNU enhanced getopt (util-linux) is available or exit
getopt --test > /dev/null
if [[ $? -ne 4 ]]; then
	echo "Missing GNU getopt fom util-linux. Cannot use shell built-in getopt and getopts. Exiting."
	exit 1
fi

#supported options in short and long version
SHORT=hvk:u:a:r
LONG=help,verbose,key-type:,custom-dh,custom-ecdh:,run-acme-as:,account-key-type:,renew-domain-key

PARSED=$(getopt --options $SHORT --longoptions $LONG --name "$0" -- "$@")

#Wrong option supplied or missing argument for an option. getopt will output an error message, but we still need to exit.
if [[ $? -ne 0 ]]; then
	exit 2
fi

# use eval with "$PARSED" to properly handle the quoting
eval set -- "$PARSED"
while true; do
	case "$1" in
		-h|--help)
			echo "Syntax: $0 [options] domain.tld ChallengeDir [Alternative Names separated by spaces]"
			echo "Available options :"
				echo "-h / --help"
				echo "-v / --verbose"
				echo "-k / --key-type (RSA|ECDSA)"
				echo "-u / --run-acme-as <user>"
				echo "-a / --account-key-type (RSA|ECDSA)"
				echo "-r / --renew-domain-key"
				echo "--custom-dh"
				echo "--custom-ecdh (secp256r1|secp384r1|secp521r1)"
			exit 1
			shift
			;;
		-v|--verbose)
			v=y
			shift
			;;
		-k|--key-type)
			domain_key_type="$2"
			shift 2
			;;
		--custom-dh)
			use_custom_dh="yes"
			shift
			;;
		--custom-ecdh)
			use_custom_ecdh="$2"
			shift 2
			;;
		-u|--run-acme-as)
			acme_user="$2"
			shift 2
			;;
		-a|--account-key-type)
			account_key_type="$2"
			shift 2
			;;
		-r|--renew-domain-key)
			renew_domain_key="yes"
			shift
			;;
		--)
			shift
			break
			;;
		*)
			echo "error"
			exit 3
			;;
	esac
done

#non-option argument handling
domain=$1
challenge_dir=$2
altname=${@:3}

#user input validation
##account key type : RSA or ECDSA
if [ ! "$account_key_type" == "RSA" ] && [ ! "$account_key_type" == "ECDSA" ]; then
	echo "Supported account key type : RSA, ECDSA"
	exit 1
fi
##domain key type : RSA or ECDSA
if [ ! "$domain_key_type" == "RSA" ] && [ ! "$domain_key_type" == "ECDSA" ]; then
	echo "Supported key type : RSA, ECDSA"
	exit 1
fi
##custom ecdh curve : none or secp256r1 secp384r1 secp521r1
if [ ! -z "$use_custom_ecdh" ] && [ ! "$use_custom_ecdh" == "secp256r1" ] && [ ! "$use_custom_ecdh" == "secp384r1" ] && [ ! "$use_custom_ecdh" == "secp521r1" ]; then
	echo "Supported ECDH curves : secp256r1, secp384r1,secp521r1"
	exit 1
fi

echo "verbose: $v ; key: $key ; customDH: $use_custom_dh ; customECDH: $use_custom_ecdh ; user=$acme_user ; $domain $challenge_dir $altname"
echo "account key : $account_key_type"
echo "domain key : $domain_key_type"
echo "renew domain key : $renew_domain_key"

if [ -z $challenge_dir ]; then
	$0 --help
	exit 1
fi

#######################################################
################# END OPTION HANDLING #################
#######################################################

#this check if stdout is asigned to a terminal or not (cron)
if [ -t 1 ]; then
	mode="normal"
else
	mode="cron"
fi

#fix permissions as git is not keeping them
chmod 700 $my_dir/secrets
chmod 750 $my_dir/work
chmod 740 $my_dir/wrapper.sh

#keys and certificates location, relative to this script path
account_key="$my_dir/secrets/account.key"
domain_key="$my_dir/secrets/$domain.key"
domain_csr="$my_dir/work/$domain/$domain.csr"
domain_crt="$my_dir/work/$domain/$domain.crt"
domain_pem="$my_dir/work/$domain/$domain.pem"
intermediate="$my_dir/work/$domain/intermediate.pem"
dh_param="$my_dir/secrets/dh4096.pem"

#switch permission to user if the script is run as root
## this is needed for every file that need to be accessible by acme_tiny.py (acme_tiny.py, CSR, account key, domain work dir)
function switch_perm () {
	if [ ! -z $acme_user ]; then
		chown $acme_user:$acme_user $@
	fi
}

function make_domain_key {
	#forcing generated file to directly have user only permission
	umask u=rwx,g=,o=
	openssl genrsa 4096 > $domain_key
	#switch back to this script default umask
	umask u=rwx,g=rx,o=
}

function make_domain_csr {
	if [ "$altname" == "" ]; then
		openssl req -new -sha256 -key $domain_key -subj "/CN=$domain" -out $domain_csr
		error=$?
	else
		openssl req -new -sha256 -key $domain_key -subj "/" -reqexts LE_SAN -config <(cat /etc/ssl/openssl.cnf <(printf "[LE_SAN]\nsubjectAltName=" ; printf "DNS:%b," $domain $altname | sed 's/.$//')) -out $domain_csr
		error=$?
	fi
	#if run by root : this file must belong to $acme_user
	switch_perm $domain_csr
	if [ $error == 0 ]; then
		echo "Success !"
	else
		echo "Error when generating CSR"
		exit 1
	fi
}

#defaulting to umask 027
umask u=rwx,g=rx,o=

if [ ! -f /usr/bin/python ]; then
	echo "Missing python binary"
	exit 1
fi

if [ ! -f /usr/bin/openssl ]; then
	echo "Missing openssl binary"
	exit 1
fi

#if $acme_user is defined : we need to run as root
if [ ! -z $acme_user ] && [ ! "`whoami`" == "root" ]; then
	echo "I am configured to be run as root user only"
	exit 1
fi

#if $acme_user is undefined : we should not run as root
if [ -z $acme_user ] && [ "`whoami`" == "root" ]; then
	echo "I am not configured to run as root"
	exit 1
fi

#DH parameter check and generation
if [ "$use_custom_dh" == "yes" ]; then
	openssl dhparam -in $dh_param -check -text &> /dev/null
	error=$?
	if [ ! $error == 0 ]; then
		echo "Missing or invalid custom DH parameter"
		#exit if we are running in crontab because we cannot continue without user interaction
		if [ "$mode" == "cron" ]; then
			echo "[DISASTER] Autorenewing failed. You need to check what went wrong and launch this script manually or your site will be unreachable as soon as your previous certificate expire"
			exit 1
		fi
		declare -l useraction #force action var to lowercase
		read -p "Would you like to generate a new 4096bit DH parameter now (this might take a very long time) ? (yes/no) " useraction
		if [ "$useraction" == "yes" ]; then
			openssl dhparam 4096 -out $dh_param
		else
			echo "You asked for a custom dh parameter in configuration, but denied it here. Cannot continue."
			echo "You can also provide your own DH parameter in PEM format at $dh_param"
			exit 1
		fi
	fi
fi

#download latest version of acme tiny if missing
if [ ! -f $my_dir/acme_tiny.py ]; then
	echo "Downloading required script acme_tiny.py"
	wget -nv -nc -O $my_dir/acme_tiny.py $acme_tiny_url
	if [ ! $? -eq 0 ]; then
		rm -f $my_dir/acme_tiny.py
		echo "Failed downloading acme_tiny.py. Exiting"
		exit 1
	fi
	#if run by root : this script must belong to $acme_user
	switch_perm $my_dir/acme_tiny.py
fi

#create a working directory for the domain
if [ ! -d $my_dir/work/$domain ]; then
	#need permission rwxr-x--- (set by umask)
	mkdir $my_dir/work/$domain
	#if run by root : this directory must belong to $acme_user
	switch_perm $my_dir/work/$domain
fi

#checking account key validity
openssl rsa -noout -text -in $account_key &> /dev/null
error=$?
if [ ! $error == 0 ] ; then
	echo "No account key or invalid account key."
	#exit if we are running in cron mode as we can't continue without an account key
	if [ "$mode" == "cron" ]; then
		echo "[DISASTER] Autorenewing failed. You need to check what went wrong and launch this script manually or your site will be unreachable as soon as your previous certificate expire"
		exit 1
	fi
	declare -l useraction #force action var to lowercase
	read -p "Would you like to generate a new account key now ? (yes/no) " useraction
	if [ "$useraction" == "yes" ]; then
		#forcing generated file to directly have user only permission
		umask u=rwx,g=,o=
		openssl genrsa 4096 > $account_key
		#switch back to this script default umask
		umask u=rwx,g=rx,o=
		#if run by root : this key must belong to $acme_user
		switch_perm $account_key
	else
		echo "If you already have a valid account key, place it in PEM format at $account_key and assure it is readable by users `whoami` and $acme_user"
		echo "Cannot continue without a valid account key. Exiting."
		exit 1
	fi
fi


#Force a new domain key to be generated
if [ "$renew_domain_key" == "yes" ]; then
	echo "Forcing domain key renew"
	make_domain_key
#Don't enforce a new domain key, so we need to check if current domain key exists & is valid
else
	#Check if domain RSA key exists. Create it if it does not exist.
	openssl rsa -noout -text -in $domain_key &> /dev/null
	error=$?
	if [ ! $error == 0 ]; then
		echo "Missing or invalid domain key for $domain."
		#exit if we are running in cron mode as we need user interaction otherwise
		if [ "$mode" == "cron" ]; then
			echo "[DISASTER] Autorenewing failed. You need to check what went wrong and launch this script manually or your site will be unreachable as soon as your previous certificate expire"
			exit 1
		fi
		declare -l useraction #force action var to lowercase
		read -p "Would you like to generate a new domain key now ? (yes/no) " useraction
		if [ "$useraction" == "yes" ]; then
			make_domain_key
		else
			#can't continue without a key
			echo "Cannot continue without a valid key file for $domain. Exiting"
			exit 1
		fi
	fi
fi

#If we force a new domain key, we need a new csr too
if [ "$renew_domain_key" == "yes" ]; then
        echo "New domain key detected, creating a new csr too"
        make_domain_csr
#no new domain key made, checking current csr validity
else
	#Check if domain CSR exists.
	openssl req -in $domain_csr -noout -text &> /dev/null
	error=$?
####TODO : check if csr match key using modulus ?
	if [ ! $error == 0 ]; then
		echo "Missing or invalid domain CSR for $domain"
		#exit if we are running in cron mode as we need user interaction otherwise
		if [ "$mode" == "cron" ]; then
			echo "[DISASTER] Autorenewing failed. You need to check what went wrong and launch this script manually or your site will be unreachable as soon as your previous certificate expire"
			exit 1
		fi
		declare -l useraction #force action var to lowercase
		read -p "Would you like to generate a new domain CSR now ? (yes/no) " useraction
		if [ "$useraction" == "yes" ]; then
			read -p "I am going to generate a new CSR for $domain and these alternatives names : $altname. Confirm ? (yes/no) " useraction
			if [ "$useraction" == "yes" ]; then
				make_domain_csr
			else
				#can't continue without a CSR
				exit 1
			fi
		else
			#can't continue without CSR
			echo "Cannot continue without a valid CSR. Exiting"
			exit 1
		fi
	fi
fi

#check if challenge_dir is writeable by the user running the script or by $acme_user if the script is run by root
if [ ! -z $acme_user ]; then
	is_writeable=$(su $acme_user -c "test -w '$challenge_dir'" && echo yes)
	user=$acme_user
else
	is_writeable=$(test -w "$challenge_dir" && echo yes)
	user=`whoami`
fi
if [ ! "$is_writeable" == "yes"  ]; then
	echo "Challenge directory $challenge_dir is not writeable by $user user. Aborting."
	echo "If the directory is existing, check that $user user is in the group of $challenge_dir directory."
	if [ "$mode" == "cron" ]; then echo "[DISASTER] Autorenewing failed. You need to check what went wrong and launch this script manually or your site will be unreachable as soon as your previous certificate expire"; fi
	exit 1
fi

if [ ! -z $acme_user ]; then #running as root so we switch to $acme_user for running acme_tiny.py
	su $acme_user -c "umask u=rwx,go=rx ;\
		python $my_dir/acme_tiny.py --account-key $account_key --csr $domain_csr --acme-dir $challenge_dir > $domain_crt ;\
		chmod o-r $domain_crt ;\
		umask u=rwx,g=rx,o="
else #running as user
	#defaulting to umask 022 in order to make sure the created challenge file in acme-dir is world- (mainly webserver-) readable
	umask u=rwx,go=rx
	python $my_dir/acme_tiny.py --account-key $account_key --csr $domain_csr --acme-dir $challenge_dir > $domain_crt
	#we don't want certificate to be readable by anyone else
	chmod o-r $domain_crt
	#Switching back to umask 027
	umask u=rwx,g=rx,o=
fi

openssl x509 -in $domain_crt -text -noout &> /dev/null
error=$?
if [ ! $error == 0 ] ; then
	echo "ERROR: ACME output is not a valid x509 certificate. Something went wrong. Exiting."
	if [ "$mode" == "cron" ]; then echo "[DISASTER] Autorenewing failed. You need to check what went wrong and launch this script manually or your site will be unreachable as soon as your previous certificate expire"; fi
	exit 1
fi

echo "Downloading LetsEncrypt intermediate certificate"
#wget --quiet -O $intermediate.new $le_intermediate_url			# old method using direct pem download, but subject to LE changes. See https://github.com/diafygi/acme-tiny/issues/115
wget -O - $le_intermediate_url | openssl x509 -inform der -outform pem -out $intermediate.new
openssl x509 -in $intermediate.new -text -noout &> /dev/null
error=$?
if [ ! $error == 0 ] ; then
	echo "ERROR: I have failed downloading a valid LetsEncrypt intermediate certificate. Exiting"
	if [ "$mode" == "cron" ]; then echo "[DISASTER] Autorenewing failed. You need to check what went wrong and launch this script manually or your site will be unreachable as soon as your previous certificate expire"; fi
	exit 1
fi

#Final stage. This is only done if all preceding test succeeded.
#This means that, if anything went wrong during autorenew, $intermediate and $domain_pem will still be valid and wont make your site unreachable when apache restart.
echo "All good, you now have a new signed certificate for $domain !"
mv $intermediate.new $intermediate
cat $domain_crt $intermediate > $domain_pem #we are bundling LE signed certificate with LE intermediate certificate as apache SSLCertificateFile allow this since version 2.4.8 (certificates must be sorted from leaf to root)

# Add custom DH parameters and an EC curve name for ephemeral keys in $domain_pem ; see http://httpd.apache.org/docs/current/mod/mod_ssl.html#sslcertificatefile
if [ "$use_custom_dh" == "yes" ]; then
	cat $dh_param >> $domain_pem
fi
if [ $use_custom_ecdh ]; then
	openssl ecparam -name $use_custom_ecdh >> $domain_pem
fi

exit 0
