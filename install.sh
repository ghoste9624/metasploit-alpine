#!/bin/sh
#
# (c) 2024 Francesco Colista
# fcolista@alpinelinux.org
#
# Configure metasploit to run as $USER
#

_yn() {                                                                            
    case $(echo $1 | tr '[A-Z]' '[a-z]') in                                                  
        y|yes) return 0 ;;                                                                   
        *) return 1 ;;                                                                       
    esac                                   
}

_install_postgresql() {
        apk add postgresql
        rc-service postgresql setup && rc-service postgresql start
        rc-update add postgresql
}

if grep -q docker /proc/1/cgroup; then echo "This script is not made to be run inside a docker container" && exit 1; fi

if [ "$(id -u)" -ne 0 ]; then
        echo 'This script must be run by root' >&2
        exit 1
fi

echo -e "\n*** METASPLOIT INSTALL FOR ALPINE LINUX ***\n"
echo "==> Account configuration."
read -p "+ Username : " USER

if ! grep -q $USER /etc/passwd; then 
    sudo -l -U $USER &>/dev/null
    if [ "$?" -ne "0" ]; then 
        echo "!!! BEWARE: The user $USER will be automatically added among sudoers with all permissions"
        echo "$USER     ALL=(ALL:ALL) ALL" >> /etc/sudoers
        adduser $USER; 
    fi
fi

apk update && apk upgrade -U -a && \
apk add alpine-sdk ruby-dev libffi-dev\
        openssl-dev readline-dev sqlite-dev \
        autoconf bison libxml2-dev postgresql-dev \
        libpcap-dev yaml-dev subversion git sqlite \
        ruby-bundler zlib-dev ruby-io-console ruby-nokogiri \
        ncurses ncurses-dev nmap ruby

gem install wirble sqlite3 rubygems-update && \
update_rubygems && \
gem install --no-document bundler -v '2.1.4'

mkdir -p /opt && cd /opt

git clone https://github.com/rapid7/metasploit-framework.git
git config --global --add safe.directory '/opt/metasploit-framework'
chown -R $USER /opt/metasploit-framework
cd metasploit-framework
bundle install --gemfile /opt/metasploit-framework/Gemfile

cat - <<EOF | su - $USER
mkdir -p /home/$USER/.msf4
mkdir -p /home/$USER/.bundle
#sudo bundle install --gemfile /opt/metasploit-framework/Gemfile
EOF

for MSF in $(ls msf*); do 
        if ! [ -L /usr/local/bin/$MSF ]; then
                ln -s /opt/metasploit-framework/$MSF /usr/local/bin/$MSF;
        fi
done

apk info -eq postgresql
if [ "$?" -ne "0" ]; then
        echo "PostgreSQL is not installed. It is possibile to run Metasploit without Postgres, but it's slower"
        read -p "Do you want to install and configure PostgresQL for Metasploit? (y/n)" yn                                                                            
             _yn $yn && _install_postgresql || \
                echo "Will continue without postgresql support"
                export NOPSQL=1   
else
        service postgresql status>/dev/null
        if [ "$?" -ne "0" ]; then
                echo "PostgreSQL is not running.."
                pgdir=$(apk info -e postgresql)
                echo "PGDIR set to $pgdir"
                if ! [ -d /usr/lib/$pgdir ]; then
                        rc-service postgresql setup && rc-service postgresql start
                else
                        rc-service postgresql start
                fi
        fi
                echo " ==> Database configuration "
                read -p "+ DB User: " DBUSER
                read -p "+ DB Password: " DBPASS
                read -p "+ DB Name: " DBNAME
        
                cat<<EOF
==> Those are the settings you choosed:
DBUser: $DBUSER
DBPass: $DBPASS
DBName: $DBNAME
EOF

                read -p "Continue (y/n)?" yn
                _yn yn && \ 
                (psql -U postgres<<EOF
CREATE USER $DBUSER WITH PASSWORD '"$DBPASS"' ;
CREATE DATABASE $DBNAME OWNER $DBUSER;
grant ALL ON DATABASE $DBNAME TO $DBUSER;
EOF

                cat<<EOF>/home/$USER/.msf4/database.yml
production:
 adapter: postgresql
 database: $DBNAME
 username: $DBUSER
 password: $DBPASS
 host: 127.0.0.1
 port: 5432
 pool: 75
 timeout: 5
EOF
)|| exit 1
fi
if [ -n "$NOPSQL" ]; then
        su - $USER -c 'msfconsole'
else
        su - $USER -c 'msfconsole -x "db_connect $DBUSER:$DBPASS@127.0.0.1:5432/$DBNAME"'
fi
