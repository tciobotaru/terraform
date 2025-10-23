#!/bin/bash
# Install Apache and create a simple webpage showing the hostname
apt-get update
apt-get install -y apache2
hostname > /var/www/html/index.html
systemctl enable apache2
systemctl start apache2
