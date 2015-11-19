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

if [ -n "${CASSANDRA_ENABLE_SSL}" ]; then
  sed -ri "s|^.*(internode_encryption:).*$|    internode_encryption: ${CASSANDRA_INTERNODE_ENCRYPTION}|" "$CASSANDRA_CONFIG/cassandra.yaml"
  sed -ri "s|^.*(keystore:).*$|    keystore: ${CASSANDRA_KEYSTORE_PATH}|" "$CASSANDRA_CONFIG/cassandra.yaml"
  sed -ri "s|^.*(keystore_password:).*$|    keystore_password: ${CASSANDRA_KEYSTORE_PASSWORD}|" "$CASSANDRA_CONFIG/cassandra.yaml"
  sed -ri "s|^.*(truststore:).*$|    truststore: ${CASSANDRA_TRUSTSTORE_PATH}|" "$CASSANDRA_CONFIG/cassandra.yaml"
  sed -ri "s|^.*(truststore_password:).*$|    truststore_password: ${CASSANDRA_TRUSTSTORE_PASSWORD}|" "$CASSANDRA_CONFIG/cassandra.yaml"

  if [ -n "${CASSANDRA_SSL_PROTOCOL}" ]; then
    sed -ri "s|^.*(protocol:).*$|    protocol: ${CASSANDRA_SSL_PROTOCOL}|" "$CASSANDRA_CONFIG/cassandra.yaml"
  fi

  if [ -n "${CASSANDRA_SSL_ALGORITHM}" ]; then
    sed -ri "s|^.*(algorithm:).*$|    algorithm: ${CASSANDRA_SSL_ALGORITHM}|" "$CASSANDRA_CONFIG/cassandra.yaml"
  fi

  if [ -n "${CASSANDRA_SSL_STORE_TYPE}" ]; then
    sed -ri "s|^.*(store_type:).*$|    store_type: ${CASSANDRA_SSL_STORE_TYPE}|" "$CASSANDRA_CONFIG/cassandra.yaml"
  fi

  if [ -n "${CASSANDRA_SSL_CIPHER_SUITES}" ]; then
    sed -ri "s|^.*(cipher_suites:).*$|    cipher_suites: [${CASSANDRA_SSL_CIPHER_SUITES}]|" "$CASSANDRA_CONFIG/cassandra.yaml"
  fi

  sed -ri "s|^.*(require_client_auth:).*$|    require_client_auth: ${CASSANDRA_REQUIRE_CLIENT_AUTH}|" "$CASSANDRA_CONFIG/cassandra.yaml"
  sed -ri "s|^    enabled:.*$|    enabled: ${CASSANDRA_REQUIRE_CLIENT_AUTH}|" "$CASSANDRA_CONFIG/cassandra.yaml"
fi

if [ -n "${CASSANDRA_AUTHENTICATOR}" ]; then
  sed -ri "s|^authenticator:.*$|authenticator: ${CASSANDRA_AUTHENTICATOR}|" "$CASSANDRA_CONFIG/cassandra.yaml"
fi

if [ -n "${CASSANDRA_ENABLE_JMX_AUTHENTICATION}" ]; then
  export LOCAL_JMX="no"

  jvm_path=`update-java-alternatives -l | awk '{print $3}'`
  cp $jvm_path/jre/lib/management/jmxremote.password.template $CASSANDRA_CONFIG/jmxremote.password
  chmod 400 /etc/cassandra/jmxremote.password

  sed -ri 's|^(# )?monitorRole.*|monitorRole QED|' "$CASSANDRA_CONFIG/jmxremote.password"
  sed -ri 's|^(# )?controlRole.*|controlRole R&D|' "$CASSANDRA_CONFIG/jmxremote.password"

  if [ -n "${CASSANDRA_ADMIN_USER}" -a -n "${CASSANDRA_ADMIN_PASSWORD}" ]; then
    echo "${CASSANDRA_ADMIN_USER} ${CASSANDRA_ADMIN_PASSWORD}" >> "$CASSANDRA_CONFIG/jmxremote.password"
    echo "${CASSANDRA_ADMIN_USER} readwrite" >> "$jvm_path/jre/lib/management/jmxremote.access"
  else
    cassandra_pwd=$( [ -z "${CASSANDRA_PASSWORD}" ] && echo "cassandra" || echo "${CASSANDRA_PASSWORD}" )
    echo "cassandra ${cassandra_pwd}" >> "$CASSANDRA_CONFIG/jmxremote.password"
    echo "cassandra readwrite" >> "$jvm_path/jre/lib/management/jmxremote.access"
  fi

  if [ -n "${CASSANDRA_ENABLE_JMX_SSL}" ]; then
    sed -ri 's|^.*(-Djavax.net\.ssl\.keyStore=).*|  JVM_OPTS="$JVM_OPTS -Djavax.net.ssl.keyStore='"${CASSANDRA_KEYSTORE_PATH}"'"|' "$CASSANDRA_CONFIG/cassandra-env.sh"
    sed -ri 's|^.*(-Djavax\.net\.ssl\.keyStorePassword=).*|  JVM_OPTS="$JVM_OPTS -Djavax.net.ssl.keyStorePassword='"${CASSANDRA_KEYSTORE_PASSWORD}"'"|' "$CASSANDRA_CONFIG/cassandra-env.sh"
    sed -ri 's|^.*(-Djavax\.net\.ssl\.trustStore=).*|  JVM_OPTS="$JVM_OPTS -Djavax.net.ssl.trustStore='"${CASSANDRA_TRUSTSTORE_PATH}"'"|' "$CASSANDRA_CONFIG/cassandra-env.sh"
    sed -ri 's|^.*(-Djavax\.net\.ssl\.trustStorePassword=).*|  JVM_OPTS="$JVM_OPTS -Djavax.net.ssl.trustStorePassword='"${CASSANDRA_TRUSTSTORE_PASSWORD}"'"|' "$CASSANDRA_CONFIG/cassandra-env.sh"
    sed -ri 's|^.*(-Dcom\.sun\.management\.jmxremote\.ssl\.need\.client\.auth=).*|  JVM_OPTS="$JVM_OPTS -Dcom.sun.management.jmxremote.ssl.need.client.auth=true"|' "$CASSANDRA_CONFIG/cassandra-env.sh"
    sed -ri 's|^.*(-Dcom\.sun\.management\.jmxremote\.registry\.ssl=).*|  JVM_OPTS="$JVM_OPTS -Dcom.sun.management.jmxremote.registry.ssl=true"|' "$CASSANDRA_CONFIG/cassandra-env.sh"

    if [ -n "${CASSANDRA_JMX_PORT}" ]; then
      sed -ri 's|^JMX_PORT=.*|JMX_PORT='"${CASSANDRA_JMX_PORT}"'|' "$CASSANDRA_CONFIG/cassandra-env.sh"

      echo "-Dcom.sun.management.jmxremote.port=${CASSANDRA_JMX_PORT}" >> /root/.cassandra/nodetool-ssl.properties
      echo "-Dcom.sun.management.jmxremote.rmi.port=${CASSANDRA_JMX_PORT}"  >> /root/.cassandra/nodetool-ssl.properties
    fi

    echo "-Djavax.net.ssl.keyStore=${CASSANDRA_KEYSTORE_PATH}" >> /root/.cassandra/nodetool-ssl.properties
    echo "-Djavax.net.ssl.keyStorePassword=${CASSANDRA_KEYSTORE_PASSWORD}" >> /root/.cassandra/nodetool-ssl.properties
    echo "-Djavax.net.ssl.trustStore=${CASSANDRA_TRUSTSTORE_PATH}" >> /root/.cassandra/nodetool-ssl.properties
    echo "-Djavax.net.ssl.trustStorePassword=${CASSANDRA_TRUSTSTORE_PASSWORD}" >> /root/.cassandra/nodetool-ssl.properties
    echo "-Dcom.sun.management.jmxremote.ssl.need.client.auth=true" >> /root/.cassandra/nodetool-ssl.properties
    echo "-Dcom.sun.management.jmxremote.registry.ssl=true" >> /root/.cassandra/nodetool-ssl.properties
  fi

fi

if [ -n "${CASSANDRA_ENABLE_SSL_DEBUG}" ]; then
  echo 'JVM_OPTS="$JVM_OPTS -Djavax.net.debug=ssl"' >> "$CASSANDRA_CONFIG/cassandra-env.sh"
fi

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
cassandra

if [ -n "${CASSANDRA_CREATE_USER}" ]; then
  # Wait for cassandra server status to be UN (Up-Normal) and create users if needed
  i="0"
  status=""
  while [ $i -lt 60 ]
  do
    status=`nodetool status | grep "${CASSANDRA_LISTEN_ADDRESS}" | awk '{print $1}'`
    if [ "${status}" = "UN" ]; then
      break
    fi

    i=$[$i + 1]
    sleep 1
  done

  if [ "${status}" = "UN" ]; then
    cqlsh_cmd=$( [ -z "${CASSANDRA_ENABLE_SSL}" ] && echo "cqlsh" || echo "cqlsh --ssl" )

    num_peers=`nodetool status | awk '/^(U|D)(N|L|J|M)/{count++} END{print count}'`
    if [ "${num_peers}" = "1" ]; then
      i="0"
      while [ $i -lt 60 ]
      do
        $cqlsh_cmd -k system -e "CREATE USER IF NOT EXISTS ${CASSANDRA_ADMIN_USER} WITH PASSWORD '${CASSANDRA_ADMIN_PASSWORD}' SUPERUSER;" && \
            $cqlsh_cmd -u $CASSANDRA_ADMIN_USER -p $CASSANDRA_ADMIN_PASSWORD -k system -e "ALTER USER cassandra WITH PASSWORD '${CASSANDRA_PASSWORD}' NOSUPERUSER;" && \
            break || true
        i=$[$i + 1]
        sleep 1
      done
    fi
  fi
fi

tail -f /var/log/cassandra/system.log
