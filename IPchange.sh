#!/usr/bin/env bash

# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2019-2020 Intel Corporation

PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

exec &> /var/log/IPchange.log
function check_eth {
    set -o pipefail # optional.
    /sbin/ethtool "$1" | grep -q "Link detected: yes"
}


if check_eth eth0; then
    echo "Fetching the Interface IP"
    old_ip=$(ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    echo "Current IP is" $old_ip
else
    echo "Not online"
fi
    
while true
do 
	new_ip=$(ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
	if [ "$new_ip" == "" ]
	then
		echo "blank new_ip" $new_ip
		continue
	fi

	if [ "$new_ip" != "" ]
	then
			
		if [ "$new_ip" == "$old_ip" ]
		then
			echo "No Change in IP detected."
		else
			cd /opt/edgecontroller	
			echo "IP change detected. New IP:- " $new_ip
			sed -i "s/$old_ip/$new_ip/g" /opt/edgecontroller/.env
			old_ip=$new_ip
			make all-down
			COMPOSE_HTTP_TIMEOUT=120 docker-compose up --build --no-deps --force-recreate -d ui
			COMPOSE_HTTP_TIMEOUT=120 docker-compose up --build --no-deps --force-recreate -d cce
			make ip-change-up
			sed -i "s/$old_ip/$new_ip/g" /opt/controller_ip/inventory.ini
			
			cmd=$(awk '{print $2}' /opt/controller_ip/node_ip)
			lines=$(wc -l /opt/controller_ip/node_ip|awk '{print $1}')
			line_number=0
			mysql_cmd=$(docker exec edgecontroller_mysql_1 mysql -uroot -ppass -D controller_ce -e 'select node_id,grpc_target from node_grpc_targets;'|tail -n+2)
			count=0
			if [ "$lines" == 0 ]
			then
        			docker exec edgecontroller_mysql_1 mysql -uroot -ppass -D controller_ce -e 'select node_id,grpc_target from node_grpc_targets;'|tail -n+2 >> /opt/controller_ip/node_ip
			else
        			for i in $(seq 1 $lines)
        			do
                			node_ini_id=$(awk '{print $1}' /opt/controller_ip/node_ip| head -$i | tail -1)
                			node_ini_ip=$(awk '{print $2}' /opt/controller_ip/node_ip| head -$i | tail -1)
                			node_db_id=$(docker exec edgecontroller_mysql_1 mysql -uroot -ppass -D controller_ce -e 'select node_id,grpc_target from node_grpc_targets;'|tail -n+2 | awk '{print $1}' | head -$i | tail -1)
                			node_db_ip=$(docker exec edgecontroller_mysql_1 mysql -uroot -ppass -D controller_ce -e 'select node_id,grpc_target from node_grpc_targets;'|tail -n+2 | awk '{print $2}' | head -$i | tail -1)
			                if [ "$node_ini_id" == "$node_db_id" ] && [ "$node_ini_ip" == "$node_db_ip" ]
			                then
			                        echo "All node IPs are same"
			                else
			                        count=$((count+1))
			                        line_number=$i
			                fi
			        done
			        if [ "$count" -gt 0 ]
			        then
			                old_node_ip=$(awk '{print $2}' /opt/controller_ip/node_ip | head -$line_number | tail -1)
			                echo $old_node_ip
			                new_node_ip=$(docker exec edgecontroller_mysql_1 mysql -uroot -ppass -D controller_ce -e 'select node_id,grpc_target from node_grpc_targets;'|tail -n+2 | awk '{print $2}' | head -$line_number | tail -1)
			                echo $new_node_ip
			                sed -i "s/$old_node_ip/$new_node_ip/g" /opt/controller_ip/node_ip
			                sed -i "s/$old_node_ip/$new_node_ip/g" /opt/controller_ip/inventory.ini
			        fi
			fi

						
			ansible-playbook -vv \
    				   /opt/controller_ip/ip_change.yml \
	                           --extra-vars "old_ip=$old_ip new_ip=$new_ip" \
                                   --inventory /opt/controller_ip/inventory.ini 
			cd /etc/ssl/certs
			rm -rf apache*
			openssl genrsa -out apache.key 2048
			openssl req -new -sha256 -key apache.key -subj "/C=IE/ST=Clare/O=ESIE/CN=$(hostname -f)" -reqexts SAN -config <(cat /etc/pki/tls/openssl.cnf <(printf "[SAN]\nsubjectAltName=IP:$new_ip")) -out apache.csr
			openssl x509 -req -in apache.csr -CA cert.pem -CAkey key.pem -CAcreateserial -out apache.crt -days 500 -sha256	
			sed -i 's|^SSLCertificateFile.*$|SSLCertificateFile /etc/ssl/certs/apache.crt|g' /etc/httpd/conf.d/ssl.conf
			sed -i 's|^SSLCertificateKeyFile.*$|SSLCertificateKeyFile /etc/ssl/certs/apache.key|g' /etc/httpd/conf.d/ssl.conf
			echo "IP Change Successfully reflected"
		fi
	else
		echo "No IP detected"
	fi
sleep 5
done

