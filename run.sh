#!/bin/bash

set -e

# TODO detect if this is a restart if necessary
: ${CASSANDRA_LISTEN_ADDRESS='auto'}
if [ "$CASSANDRA_LISTEN_ADDRESS" = 'auto' ]; then
	CASSANDRA_LISTEN_ADDRESS="$(hostname --all-ip-addresses | awk '{print $2}')"
fi

: ${CASSANDRA_BROADCAST_ADDRESS="$CASSANDRA_LISTEN_ADDRESS"}

if [ "$CASSANDRA_BROADCAST_ADDRESS" = 'auto' ]; then
	CASSANDRA_BROADCAST_ADDRESS="$(hostname --all-ip-addresses | awk '{print $2}')"
fi
: ${CASSANDRA_BROADCAST_RPC_ADDRESS:=$CASSANDRA_BROADCAST_ADDRESS}

if [ -n "${CASSANDRA_NAME:+1}" ]; then
	: ${CASSANDRA_SEEDS:="cassandra"}
fi
: ${CASSANDRA_SEEDS:="$CASSANDRA_BROADCAST_ADDRESS"}

if [ -n "${CASSANDRA_RANCHER_SERVICE_SEEDS}" ]; then
  # Loop through all the services and concat the ips
  for rancher_service in ${CASSANDRA_RANCHER_SERVICE_SEEDS//,/ } ; do
    service_ips=$(dig +short $rancher_service | awk -v ORS=, '{print $1}' | sed 's/,$//')
    SERVICE_SEEDS="${SERVICE_SEEDS},${service_ips}"
  done

 # Get the firs three IP addresses
 IFS=',' read -a SUB_SEEDS <<< "$SERVICE_SEEDS"
 SUB_SEEDS=${SUB_SEEDS[@]:0:4}
 CASSANDRA_SEEDS=${SUB_SEEDS// /,}
fi

sed -ri 's/(- seeds:) "127.0.0.1"/\1 "'"$CASSANDRA_SEEDS"'"/' "$CASSANDRA_CONFIG/cassandra.yaml"


for yaml in \
	broadcast_address \
	broadcast_rpc_address \
	cluster_name \
	endpoint_snitch \
	listen_address \
	num_tokens \
  commitlog_total_space_in_mb \
; do
	var="CASSANDRA_${yaml^^}"
	val="${!var}"
	if [ "$val" ]; then
		sed -ri 's/^(# )?('"$yaml"':).*/\2 '"$val"'/' "$CASSANDRA_CONFIG/cassandra.yaml"
	fi
done

for rackdc in dc rack; do
	var="CASSANDRA_${rackdc^^}"
	val="${!var}"

  if [ "${rackdc}" = "dc" -a -z "$val" ]; then
    val=$(curl http://rancher-metadata/latest/self/host/labels/host-region)
  fi

  if [ "${rackdc}" = "rack" -a -z "$val" ]; then
    val=$(curl http://rancher-metadata/latest/self/host/labels/host-az)
  fi

	if [ "$val" ]; then
		sed -ri 's/^('"$rackdc"'=).*/\1 '"$val"'/' "$CASSANDRA_CONFIG/cassandra-rackdc.properties"
	fi
done

# if [ -n "${CASSANDRA_ENABLE_SSL}" ]; then
# 	sed -ri 's/^(# )?('"$yaml"':).*/\2 '"$val"'/' "$CASSANDRA_CONFIG/cassandra.yaml"
# fi

# server_encryption_options:
#   internode_encryption: all
#   keystore: /Users/zznate/.ccm/sslverify/$NODE/conf/server-keystore.jks
#   keystore_password: awesomekeypass
#   truststore: /Users/zznate/.ccm/sslverify/$NODE/conf/server-truststore.jks
#   truststore_password: truststorepass
#   protocol: TLS
#   algorithm: SunX509
#   store_type: JKS
#   cipher_suites: [TLS_RSA_WITH_AES_256_CBC_SHA]
#   require_client_auth: t

# Increase RLIMIT_MEMLOCK
# We got this info from the following links:
# - http://docs.datastax.com/en/cassandra/2.0/cassandra/troubleshooting/trblshootInsufficientResources_r.html
# - http://man7.org/linux/man-pages/man7/capabilities.7.html
echo "root - memlock unlimited" >> /etc/security/limits.conf
echo "root - nofile 100000" >> /etc/security/limits.conf
echo "root - nproc 32768" >> /etc/security/limits.conf
echo "root - as unlimited" >> /etc/security/limits.conf

# Clear out system data
# http://docs.datastax.com/en/cassandra/2.0/cassandra/initialize/initializeSingleDS.html
rm -rf /var/lib/cassandra/*

# start cassandra
cassandra -f
