#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y nginx wget unzip

archive=/tmp/tech365-site.zip
site_dir=/tmp/tech365-site
wget -O "$archive" https://www.tooplate.com/zip-templates/2144_parallax_depth.zip
rm -rf "$site_dir"
mkdir -p "$site_dir" /var/www/html
unzip -q "$archive" -d "$site_dir"

index_file=$(find "$site_dir" -type f -name index.html -print -quit)
if [ -z "$index_file" ]; then
  echo "No index.html found in the downloaded site archive" >&2
  exit 1
fi

web_content_dir=$(dirname "$index_file")
find /var/www/html -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
cp -a "$web_content_dir"/. /var/www/html/
chown -R www-data:www-data /var/www/html
find /var/www/html -type d -exec chmod 755 {} +
find /var/www/html -type f -exec chmod 644 {} +
systemctl enable --now nginx
systemctl restart nginx
