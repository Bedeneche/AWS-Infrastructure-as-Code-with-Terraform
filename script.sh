#!/bin/bash
# Update the package list
sudo apt-get update

# Install Nginx
sudo apt-get install  nginx wget unzip -y
sudo  wget https://www.tooplate.com/zip-templates/2145_eco_lume.zip
sudo unzip 2145_eco_lume.zip 
sudo systemctl start nginx
sudo systemctl enable --now nginx
sudo cp -r  2145_eco_lume/* /var/www/html/
sudo chmod 777/var/www/html/index.html
sudo systemctl restart nginx
# Create a simple webpage

# Start Nginx and enable it after future reboots
