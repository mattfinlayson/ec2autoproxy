#!/bin/bash
# --------------------------------------
#
#     Title: Amazon EC2 Private Proxy Server Automation Script
#    Author: Matthew Finlayson
#     Email: matt (at) unsure (dot) org
#  Homepage: http://unsure.org
#  -------------------------------------
#   Origin 
#  -------------------------------------
#    Author: Jonathan Lumb
#     Email: jonolumb (at) gmail (dot) com
#  Homepage: http://sprayfly.com
#      File: autoproxy.sh
#   Created: June 18, 2009
#
#   Purpose: Automates the setting up of a private proxy on an Amazon EC2 Instance
#
# --------------------------------------

########### Setup EC Tools #############
# Replace with your paths and keys
export EC2_HOME= # Location of your EC2 toolkit
PATH=$EC2_HOME/bin:$PATH # Don't change this
export EC2_PRIVATE_KEY=  # EC2 Private Key
export EC2_CERT= # EC2 Certificate
export JAVA_HOME=/Library/Java/Home # Location of JAVA
export ssh_key= # Private RSA SSH Key Location
export autoproxy= # Location of the Autoproxy script and config files
############ End of Setup #############

## Define exit function used to shutdown EC2 Instance
function quit {
	echo "Initiate EC2 Instance Shutdown"
	if [ -n "$tunnel" ] # Check if a tunnel has been made or not
	then
	echo "Closing SSH Tunnel"
	ssh -i $ssh_key root@$EC2_HOST "touch /tmp/stop"
	fi	
	echo "Terminating Instance"
	$EC2_HOME/bin/ec2-terminate-instances $EC2_INSTANCE > /dev/null
	echo "Server is now shut down, bye bye!"
	exit
}

## Create an ami-23b6534a proxy instance
echo "Create an Amazon EC2 Server Instance"
export EC2_INSTANCE=`$EC2_HOME/bin/ec2-run-instances ami-23b6534a -k gsg-keypair -z us-east-1b \
    | tr '\t' '\n' | grep '^i-'`
echo "Wait for instance to load before preceding"

## Loop which waits for instance to load fully
x=0
ec2running=`$EC2_HOME/bin/ec2-describe-instances $EC2_INSTANCE | grep INSTANCE | tr '\t' '\n' | grep running`
until [ -n "$ec2running" ] # (Until unempty string is returned)
do
sleep 2
ec2running=`$EC2_HOME/bin/ec2-describe-instances $EC2_INSTANCE | grep INSTANCE | tr '\t' '\n' | grep running`
x=$(($x+1))
echo "Server not yet running, $x attempts"
if [ "$x" -ge 10 ]
then
quit
fi
done
echo "Instance running, proceed to aquire hostname"

## Retrieve Instance Hostname
echo "Retrieve Hostname for instance ${EC2_INSTANCE}"
export EC2_HOST=$(ec2-describe-instances $EC2_INSTANCE | awk '/INSTANCE/{print $4}')

# Get IP Address
export localip=`curl -s checkip.dyndns.com | grep -Eo "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"`

#  Build customized httpd.conf file to be used
echo "Building httpd.conf file"
cat $autoproxy/httpd.temp > /tmp/httpd.conf
echo "<IfModule mod_proxy.c>

ProxyRequests On

<Proxy *>
    Order deny,allow
    Deny from all
    Allow from $localip
</Proxy>

</IfModule>" >> /tmp/httpd.conf

### Use Rsync to put httpd.conf on remote instance and restart apache
sleep 15
echo "Sync httpd.conf to instance and restart apache"
echo "Trying: rsync --delete --compress --stats --progress --include-from=$autoproxy/httpd_include -e 'ssh -i $ssh_key' -avz /tmp/ root@$EC2_HOST:/etc/httpd/conf > /tmp/rsync_log.txt"
rsync --delete --compress --stats --progress --include-from=$autoproxy/httpd_include -e "ssh -i $ssh_key" -avz /tmp/ root@$EC2_HOST:/etc/httpd/conf > /tmp/rsync_log.txt
echo "Trying: ssh -i $ssh_key root@$EC2_HOST 'sudo /etc/init.d/httpd restart'"
ssh -i $ssh_key root@$EC2_HOST "sudo /etc/init.d/httpd restart"

## Do we want to create an SSH Tunnel?
read -p "Do you want to create an SSH tunnel to the proxy server (y/n)?"
if [ "$REPLY" == "y" ]
then
# Make Tunnel, only terminate when file /tmp/stop is created
export tunnel=yes
echo "Creating HTTP Tunnel to EC2 Instance in the background"
ssh -f -i $ssh_key -D 9999 root@$EC2_HOST "while [ ! -f /tmp/stop ]; do echo > /dev/null; done" &
fi

# Proxy is now running, wait for user input to initiate shutdown
until [ "$keypress" = "stop" ]
do
echo "Proxy is now running, to shutdown proxy type \"stop\" in the terminal"
read -n 4 keypress
done
sleep 1
# Initiate shutdown of EC2 instance 
echo -e "\n Now shutting down EC2 instance"
quit
exit
