# acme-tiny wrapper

This tiny bash script is a wrapper for https://github.com/diafygi/acme-tiny allowing easy deployment and management of LetsEncrypt SSL/TLS certificates.
Syntax: ./wrapper.sh domain.tld ChallengeDir [Alternative Names separated by spaces]

## Usage Example
This example suppose you are logged in as root user.

### Create a dedicated user for the script :
```
adduser --disabled-login --disabled-password acme
echo "acme:   root" >> /etc/aliases
postalias /etc/aliases
```

### Clone the repository :
```
su - acme
git clone https://github.com/pfoo/acme-tiny-wrapper.git
cd acme-tiny-wrapper
cp config.cf.example config.cf
exit
```

### Create a working challenge architecture
If order to have challenge working you need to
- create a challenge directory somewhere inside or outside your documentroot
- allow the user acme to write inside this challenge directory
- allow apache to read the challenge directory
- the challenge file -created by acme-tiny- will belong to user acme and be readable by user, group and other.

If you are using apache-mpm-itk, each of your site should belong to a different userid and groupid.  
For example, the site example.tld which has its document root in /home/example.tld/www/ is accessible in read-write by user example.tld and read-only by group example.tld and no permission at all for other.

As user example.tld, create the challenge directory and allow group writing in it :
```
su - example.tld
mkdir /home/example.tld/www/challenges
chmod g+w /home/example.tld/www/challenges
exit
```

Add acme user to group example.tld
```
usermod -a -G example.tld acme
```

### Configure apache 
Add this configuration in your site apache configuration :
```
<Directory "/home/example.tld/www/challenges/">
    DirectoryIndex disabled
    Options -Indexes -FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>
Alias /.well-known/acme-challenge "/home/example.tld/www/challenges"
```

### Run the script 

There are two way of running this script : as user or as root.<br>
Running it as user is safer if you don't trust this script entirely, but will allow acme-tiny.py to read your private keys.<br>
Running it as root will prevent acme-tiny.py from reading your private keys.<br>
In both case, acme-tiny.py will be run as unprivileged user.

By default, the script is running as unprivileged user. If you wish to run this script as root, you need to uncomment and 
set acme_user variable in config.cf to the user that should run acme-tiny.py (acme in this README).
Please, do not switch from root-mode to user-mode or vice versa if you have already run this script once (this will lead to
inconsistent files and directories permissions and is unsupported for now).

#### Run the script as user
Make sure the variable acme_user in config.cf is commented (it should be by default).
```
su - acme
/home/acme/acme-tiny-wrapper/wrapper.sh example.tld /home/example.tld/www/challenges/ www.example.tld
```

#### Run the script as root
Uncomment the variable acme_user in config.cf and define it to the user that should run acme-tiny.py (acme if you followed this README)
```
/home/acme/acme-tiny-wrapper/wrapper.sh example.tld /home/example.tld/www/challenges/ www.example.tld
```

### Create cron jobs

#### If running as user
Access crontabs :
```
su - acme
crontab -e
```

Add this line to renew your certificate every 15th day of month at 4AM :
```
0 4     15 * * /home/acme/acme-tiny-wrapper/wrapper.sh example.tld /home/example.tld/www/challenges/ www.example.tld
```

Then edit /etc/crontab in order to reload apache. Make sure this is done *after* certificate renew (here at 4:15AM)
```
15 4    15 * *  root    /etc/init.d/apache2 reload
```

#### If running as root
Edit /etc/crontab
```
0 4     15 * *  root    /home/acme/acme-tiny-wrapper/wrapper.sh example.tld /home/example.tld/www/challenges/ www.example.tld
15 4    15 * *  root    /etc/init.d/apache2 reload
```

If you are renewing multiple certificates, make sure the cron reloading apache is always started AFTER every certificate renewing are done.
