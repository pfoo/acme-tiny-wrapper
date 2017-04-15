## This README suppose you are logged in as root user.

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

If you are using apache-mpm-itk, each of your site should belong to a different userid and groupid
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

There are two way of running this script : as user or as root.
Running it as user is safer if you don't trust this script entirely, but will allow acme-tiny.py to read your private keys
Running it as root will prevent acme-tiny from reading your private keys
In both case, acme-tiny.py will be run as unprivileged user

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
