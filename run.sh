#!/bin/bash

set -e

: ${CASSANDRA_USERNAME='cassandra'}
: ${CASSANDRA_PASSWORD='cassandra'}
: ${USE_RANCHER_IP:=false}
: ${CASSANDRA_ENABLE_SSL:=false}
: ${CASSANDRA_ENABLE_JMX_AUTHENTICATION:=false}
: ${CASSANDRA_ENABLE_JMX_SSL:=false}
: ${CASSANDRA_ENABLE_SSL_DEBUG:=false}
: ${CASSANDRA_ENABLE_G1GC:=false}

# TODO detect if this is a restart if necessary
: ${CASSANDRA_LISTEN_ADDRESS='auto'}
if [ "$CASSANDRA_LISTEN_ADDRESS" = 'auto' ]; then
	if [ $USE_RANCHER_IP == true ]; then
		CASSANDRA_LISTEN_ADDRESS=$(curl http://rancher-metadata/2015-12-19/self/host/agent_ip)
	else
		CASSANDRA_LISTEN_ADDRESS="$(hostname --all-ip-addresses | awk '{print $1}')"
	fi
fi

: ${CASSANDRA_BROADCAST_ADDRESS="$CASSANDRA_LISTEN_ADDRESS"}
if [ "$CASSANDRA_BROADCAST_ADDRESS" = 'auto' ]; then
	CASSANDRA_BROADCAST_ADDRESS="$(hostname --all-ip-addresses | awk '{print $1}')"
fi
: ${CASSANDRA_BROADCAST_RPC_ADDRESS:=$CASSANDRA_BROADCAST_ADDRESS}

# If we're given a list of rancher services for seeds, then use the ips
# from these services.
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

: ${CASSANDRA_SEEDS:="$CASSANDRA_BROADCAST_ADDRESS"}
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
		sed -ri 's/^('"$rackdc"'=).*/\1'"$val"'/' "$CASSANDRA_CONFIG/cassandra-rackdc.properties"
	fi
done

# Here we set those cassandra properties that are needed to enable SSL
if [ $CASSANDRA_ENABLE_SSL = true ]; then
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

# Here we override the cassandra authenticator parameter
if [ -n "${CASSANDRA_AUTHENTICATOR}" ]; then
  sed -ri "s|^authenticator:.*$|authenticator: ${CASSANDRA_AUTHENTICATOR}|" "$CASSANDRA_CONFIG/cassandra.yaml"

  # Here we override the user and password in the cqlshrc file
  if [ "${CASSANDRA_AUTHENTICATOR}" = "PasswordAuthenticator" ]; then

    cassandra_user=$( [ -z "${CASSANDRA_ADMIN_USER}" ] && echo "${CASSANDRA_USERNAME}" || echo "${CASSANDRA_ADMIN_USER}" )
    cassandra_pwd=$( [ -z "${CASSANDRA_ADMIN_PASSWORD}" ] && echo "${CASSANDRA_PASSWORD}" || echo "${CASSANDRA_ADMIN_PASSWORD}" )
    sed -ri 's|^username =.*|username = '"${cassandra_user}"'|' /root/.cassandra/cqlshrc
    sed -ri 's|^password =.*|password = '"${cassandra_pwd}"'|' /root/.cassandra/cqlshrc
  fi
fi

# Here we enable JMX access through authentication
if [ $CASSANDRA_ENABLE_JMX_AUTHENTICATION = true ]; then
  export LOCAL_JMX="no"

  jvm_path=`update-java-alternatives -l | awk '{print $3}'`
  cp $jvm_path/jre/lib/management/jmxremote.password.template $CASSANDRA_CONFIG/jmxremote.password
  chmod 400 /etc/cassandra/jmxremote.password

  sed -ri 's|^(# )?monitorRole.*|monitorRole QED|' "$CASSANDRA_CONFIG/jmxremote.password"
  sed -ri 's|^(# )?controlRole.*|controlRole R&D|' "$CASSANDRA_CONFIG/jmxremote.password"
  sed -ri 's|^.*(-Djava\.rmi\.server\.hostname=).*|  JVM_OPTS="$JVM_OPTS -Djava.rmi.server.hostname='"${CASSANDRA_LISTEN_ADDRESS}"'"|' "$CASSANDRA_CONFIG/cassandra-env.sh"

	# If we were given a specific JMX admin user and password, then set it on the jmxremote.* files
	# Otherwise, simply use the defined cassandra username and password
  if [ -n "${CASSANDRA_ADMIN_USER}" -a -n "${CASSANDRA_ADMIN_PASSWORD}" ]; then
    echo "${CASSANDRA_ADMIN_USER} ${CASSANDRA_ADMIN_PASSWORD}" >> "$CASSANDRA_CONFIG/jmxremote.password"
    echo "${CASSANDRA_ADMIN_USER} readwrite" >> "$jvm_path/jre/lib/management/jmxremote.access"
  else
    echo "${CASSANDRA_USERNAME} ${CASSANDRA_PASSWORD}" >> "$CASSANDRA_CONFIG/jmxremote.password"
    echo "${CASSANDRA_USERNAME} readwrite" >> "$jvm_path/jre/lib/management/jmxremote.access"
  fi

  # Here we enable SSL access for JMX
  if [ $CASSANDRA_ENABLE_JMX_SSL = true ]; then
    sed -ri 's|^.*(-Dcom\.sun\.management\.jmxremote\.ssl=).*|  JVM_OPTS="$JVM_OPTS -Dcom.sun.management.jmxremote.ssl=true"|' "$CASSANDRA_CONFIG/cassandra-env.sh"
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

if [ $CASSANDRA_ENABLE_SSL_DEBUG = true ]; then
  echo 'JVM_OPTS="$JVM_OPTS -Djavax.net.debug=ssl"' >> "$CASSANDRA_CONFIG/cassandra-env.sh"
fi

if [ $CASSANDRA_ENABLE_G1GC = true ]; then
	sed -ri 's|^.*(-Xmn\$\{HEAP_NEWSIZE\}).*|# JVM_OPTS="$JVM_OPTS -Xmn${HEAP_NEWSIZE}"|' "$CASSANDRA_CONFIG/cassandra-env.sh"

	# Clear existing GC options
	sed -ir '/GC tuning options/,/GC logging options/c\# GC logging options' "$CASSANDRA_CONFIG/cassandra-env.sh"

	# Add G1GC options
	sed -ir 's/# GC logging options/# G1GC options\nJVM_OPTS="\$JVM_OPTS \-XX:\+UseG1GC"\nJVM_OPTS="\$JVM_OPTS \-XX:MaxGCPauseMillis=500"\nJVM_OPTS="\$JVM_OPTS \-XX:G1RSetUpdatingPauseTimePercent=5"\nJVM_OPTS="\$JVM_OPTS \-XX:+AlwaysPreTouch"\nJVM_OPTS="\$JVM_OPTS \-XX:\-UseBiasedLocking"\nJVM_OPTS="\$JVM_OPTS \-XX:\+UseTLAB \-XX:\+ResizeTLAB"\nJVM_OPTS="\$JVM_OPTS \-XX:\+PerfDisableSharedMem"\nJVM_OPTS="\$JVM_OPTS \-XX:CompileCommandFile=\$CASSANDRA_CONF\/hotspot_compiler"\n\n# GC logging options/' "$CASSANDRA_CONFIG/cassandra-env.sh"

	# Add +UseCondCardMark back since it was removed when we cleared GC options above
	sed -ir 's/# GC logging options/if [ "$JVM_ARCH" = "64-Bit" ] ; then\n    JVM_OPTS="$JVM_OPTS -XX:+UseCondCardMark"\nfi\n\n# GC logging options/' "$CASSANDRA_CONFIG/cassandra-env.sh"

fi


# Increase RLIMIT_MEMLOCK
# We got this info from the following links:
# - http://docs.datastax.com/en/cassandra/2.0/cassandra/troubleshooting/trblshootInsufficientResources_r.html
# - http://man7.org/linux/man-pages/man7/capabilities.7.html
echo "root - memlock unlimited" >> /etc/security/limits.conf
echo "root - nofile 100000" >> /etc/security/limits.conf
echo "root - nproc 32768" >> /etc/security/limits.conf
echo "root - as unlimited" >> /etc/security/limits.conf

# start cassandra
cassandra -f
