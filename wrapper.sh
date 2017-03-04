#! /bin/bash

domain="networklab.fr"
altname="www.networklab.fr plop.networklab.fr prout.networklab.fr"
challenge_dir="/home/pfoo/Documents/dev/github/acme-tiny-wrapper/plop/"

mode=$1

acme_url="https://raw.githubusercontent.com/diafygi/acme-tiny/master/acme_tiny.py"

my_source="${BASH_SOURCE[0]}"
while [ -h "$my_source" ]; do # resolve $my_source until the file is no longer a symlink
  my_dir="$( cd -P "$( dirname "$my_source" )" && pwd )"
  my_source="$(readlink "$my_source")"
  [[ $my_source != /* ]] && my_source="$my_dir/$my_source" # if $my_source was a relative symlink, need to resolve its relative to the path where the symlink file was located
done
my_dir="$( cd -P "$( dirname "$my_source" )" && pwd )/"

account_key="$my_dir/secrets/account.key"
domain_key="$my_dir/secrets/$domain.key"
domain_csr="$my_dir/work/$domain/$domain.csr"
domain_crt="$my_dir/work/$domain/$domain.crt"
domain_pem="$my_dir/work/$domain/$domain.pem"
intermediate="$my_dir/work/$domain/intermediate.pem"

#defaulting to umask 027
umask u=rwx,g=rx,o=

if [ ! -f /usr/bin/python ]; then
	echo "Missing python binary"
	exit 1
fi

#download latest version of acme tiny if missing
if [ ! -f $my_dir/acme_tiny.py ]; then
	wget -O $my_dir/acme_tiny.py https://raw.githubusercontent.com/diafygi/acme-tiny/master/acme_tiny.py
fi

#create a working directory for the domain
if [ ! -d $my_dir/work/$domain ]; then
	#need permission rwxr-x--- (set by umask)
	mkdir $my_dir/work/$domain
fi

#checking account key validity
openssl rsa -noout -text -in $account_key &> /dev/null
error=$?
if [ ! $error == 0 ] ; then
	echo "No account key or invalid account key."
	#exit if we are running in cron mode as we can't continue without an account key
	if [ "$mode" == "cron" ]; then
		echo "Autorenewing failed. You need to check what went wrong and launch this script manually or your site will be unreachable as soon as your previous certificate expire"
		exit 1
	fi
	declare -l useraction #force action var to lowercase
	read -p "Would you like to generate a new account key now ? (yes/no) " useraction
	if [ "$useraction" == "yes" ]; then
		#forcing generated file to directly have user only permission
		umask u=rwx,g=,o=
		openssl genrsa 8192 > $account_key
		umask u=rwx,g=rx,o=
	else
		exit 1
	fi
fi

#Check if domain RSA key exists. Create it if it does not exist.
openssl rsa -noout -text -in $domain_key &> /dev/null
error=$?
if [ ! $error == 0 ]; then
	echo "Missing or invalid domain key for $domain."
	#exit if we are running in cron mode as we need user interaction otherwise
	if [ "$mode" == "cron" ]; then
		echo "Autorenewing failed. You need to check what went wrong and launch this script manually or your site will be unreachable as soon as your previous certificate expire"
		exit 1
	fi
	declare -l useraction #force action var to lowercase
	read -p "Would you like to generate a new domain key now ? (yes/no) " useraction
	if [ "$useraction" == "yes" ]; then
		#forcing generated file to directly have user only permission
		umask u=rwx,g=,o=
		openssl genrsa 4096 > $domain_key
		umask u=rwx,g=rx,o=
	else
		#can't continue without a key
		exit 1
	fi
fi

#Check if domain CSR exists.
openssl req -in $domain_csr -noout -text &> /dev/null
error=$?
if [ ! $error == 0 ]; then
	echo "Missing or invalid domain CSR for $domain"
	#exit if we are running in cron mode as we need user interaction otherwise
	if [ "$mode" == "cron" ]; then
		echo "Autorenewing failed. You need to check what went wrong and launch this script manually or your site will be unreachable as soon as your previous certificate expire"
		exit 1
	fi
	declare -l useraction #force action var to lowercase
	read -p "Would you like to generate a new domain CSR now ? (yes/no) " useraction
	if [ "$useraction" == "yes" ]; then
		read -p "I am going to generate a new CSR for $domain and these alternatives names : $altname. Confirm ? (yes/no) " useraction
		if [ "$useraction" == "yes" ]; then
			if [ "$altname" == "" ]; then
				openssl req -new -sha256 -key $domain_key -subj "/CN=$domain" -out $domain_csr
				error=$?
			else
				openssl req -new -sha256 -key $domain_key -subj "/" -reqexts LE_SAN -config <(cat /etc/ssl/openssl.cnf <(printf "[LE_SAN]\nsubjectAltName=" ; printf "DNS:%b," $domain $altname | sed 's/.$//')) -out $domain_csr
				error=$?
			fi
			if [ $error == 0 ]; then
				echo "Success !"
			else
				echo "Error when generating CSR"
				exit 1
			fi
		else
			#can't continue without a CSR
			exit 1
		fi
	else
		#can't continue without CSR
		exit 1
	fi
fi

#check if challenge_dir is writeable
if [ ! -d $challenge_dir ] || [ ! -w $challenge_dir ]; then
	echo "Challenge directory $challenge_dir is not writeable by `whoami` user. Abording."
	echo "If the directory is existing, check that `whoami` user is in $challenge_dir directory group"
	if [ "$mode" == "cron" ]; then echo "Autorenewing failed. You need to check what went wrong and launch this script manually or your site will be unreachable as soon as your previous certificate expire"; fi
	exit 1
fi

#defaulting to umask 022 in order to make sure the created challenge file in acme-dir is world- (mainly webserver-) readable
umask u=rwx,go=rx
python $my_dir/acme_tiny.py --account-key $account_key --csr $domain_csr --acme-dir $challenge_dir > $domain_crt
#Switching back to umask 027
umask u=rwx,g=rx,o=

openssl x509 -in $domain_crt -text -noout &> /dev/null
error=$?
if [ ! $error == 0 ] ; then
	echo "ERROR: ACME output is not a valid x509 certificate. Something went wrong. Exiting."
	if [ "$mode" == "cron" ]; then echo "Autorenewing failed. You need to check what went wrong and launch this script manually or your site will be unreachable as soon as your previous certificate expire"; fi
	exit 1
fi

wget -O $intermediate.new https://letsencrypt.org/certs/lets-encrypt-x3-cross-signed.pem
openssl x509 -in $intermediate.new -text -noout &> /dev/null
error=$?
if [ ! $error == 0 ] ; then
	echo "ERROR: $intermediate.new is not a valid x509 certificate. Exiting."
	if [ "$mode" == "cron" ]; then echo "Autorenewing failed. You need to check what went wrong and launch this script manually or your site will be unreachable as soon as your previous certificate expire"; fi
	exit 1
fi

#Final stage. This is only done if all preceding test succeeded.
#This means that, if anything went wrong during autorenew, $intermediate and $domain_pem will still be valid and wont make your site unreachable when apache restart.
mv $intermediate.new $intermediate
cat $domain_crt $intermediate > $domain_pem #we are bundling LE signed certificate with LE intermediate certificate as apache SSLCertificateFile allow this since version 2.4.8 (certificates must be sorted from leaf to root)

#todo : Allow adding custom DH parameters and an EC curve name for ephemeral keys in $domain_pem ; see http://httpd.apache.org/docs/current/mod/mod_ssl.html#sslcertificatefile

exit 0
