# Docker Cassandra

Base docker image to run a Cassandra. This is a modified copy of
[official cassandra](https://hub.docker.com/_/cassandra/). It also uses
[phusion's](https://github.com/phusion/baseimage-docker) base docker image.

Aside from the original functionality, this image has the ability to run on
Rancher and auto-discover seeds.

## Building the image

Clone the repository

        git clone https://github.com/pitrho/docker-cassandra.git
        cd docker-cassandra
        ./build.sh

De default tag for the new image is pitrho/cassadra. If you want to specify a
different tag, pass the -t flag along with the tag name:

    ./build.sh -t new/tag

Be default, the image installs version 2.2.3. If you want to install
a different version, pass the -v flag along with the version name:

    ./build.sh -v 3.0.0

## Environment Variables

When you start the cassandra image, you can adjust the configuration of the Cassandra instance by passing one or more environment variables on the docker run command line.

### CASSANDRA_LISTEN_ADDRESS
This variable is for controlling which IP address to listen for incoming connections on. The default value is auto, which will set the listen_address option in cassandra.yaml to the IP address of the container as it starts. This default should work in most use cases.

### CASSANDRA_BROADCAST_ADDRESS
This variable is for controlling which IP address to advertise to other nodes. The default value is the velue of CASSANDRA_LISTEN_ADDRESS. It will set the broadcast_address and broadcast_rpc_address options in cassandra.yaml.

Note: rpc_address is always set to the wildcard address (0.0.0.0), which means this value cannot be the wildcard address (and thus must be a specific address).

### CASSANDRA_SEEDS
This variable is the comma-separated list of IP addresses used by gossip for bootstrapping new nodes joining a cluster. It will set the seeds value of the seed_provider option in cassandra.yaml. The CASSANDRA_BROADCAST_ADDRESS will be added the the seeds passed in so that the sever will talk to itself as well.

### CASSANDRA_CLUSTER_NAME
This variable sets the name of the cluster and must be the same for all nodes in the cluster. It will set the cluster_name option of cassandra.yaml.

### CASSANDRA_NUM_TOKENS
This variable sets number of tokens for this node. It will set the num_tokens option of cassandra.yaml.

### CASSANDRA_DC
This variable sets the datacenter name of this node. It will set the dc option of cassandra-rackdc.properties. If you don't specify this variable, and you're running
on Rancher, the image will investigate the hosts and look for a label called host-region,
and use it as its DC property.

### CASSANDRA_RACK
This variable sets the rack name of this node. It will set the rack option of cassandra-rackdc.properties. If you don't specify this variable, and you're running
on Rancher, the image will investigate the hosts and look for a label called host-az,
and use it as its DC property.

### CASSANDRA_ENDPOINT_SNITCH
This variable sets the snitch implementation this node will use. It will set the endpoint_snitch option of cassandra.yml.

### CASSANDRA_ENABLE_SSL
If this variable enables the configuration for server_encryption_options and
client_encryption_options.

### CASSANDRA_INTERNODE_ENCRYPTION
This variable sets the internode_encryption value for server_encryption_options and
client_encryption_options.

### CASSANDRA_KEYSTORE_PATH
This variable sets the path to the location of the key store file under
server_encryption_options and client_encryption_options. It is assumed
that the key store will be mounted to the image using the volumes property.

### CASSANDRA_KEYSTORE_PASSWORD
This variable sets the key store password for server_encryption_options and
client_encryption_options.

### CASSANDRA_TRUSTSTORE_PATH
This variable sets the path to the location of the trust store file under
server_encryption_options and client_encryption_options. It is assumed
that the trust store will be mounted to the image using the volumes property.

### CASSANDRA_TRUSTSTORE_PASSWORD
This variable sets the trust store password for server_encryption_options and
client_encryption_options.

### CASSANDRA_SSL_PROTOCOL
This variables sets the ssl protocol for server_encryption_options and
client_encryption_options.

### CASSANDRA_SSL_ALGORITHM
This variables sets the ssl algorithm for server_encryption_options and
client_encryption_options.

### CASSANDRA_SSL_STORE_TYPE
This variables sets the ssl store type for server_encryption_options and
client_encryption_options.

### CASSANDRA_SSL_CIPHER_SUITES
This variable sets the ssl cipher suites for server_encryption_options and
client_encryption_options. You can specify multiple values using
a comma-separated list.

### CASSANDRA_REQUIRE_CLIENT_AUTH
This variable enables client_encryption_options and sets require_client_auth
under server_encryption_options and client_encryption_options.

### CASSANDRA_AUTHENTICATOR
This sets the authenticator in cassandra.yml.

### CASSANDRA_ENABLE_JMX_AUTHENTICATION
This variable enables authentication through JMX

### CASSANDRA_ENABLE_JMX_SSL
This variable enables SSL through JMX

### CASSANDRA_JMX_PORT
This variable sets the JMX_PORT in cassandra-env.sh

### CASSANDRA_ENABLE_SSL_DEBUG
This variable enables ssl debugging on the server. Don't enable this on
production, unless you are debugging ssl problems.

## Rancher Environment Variables

Aside from the environment variables listed above, this image introduces some
changes to auto discover cluster seeds in Rancher.

##CASSANDRA_RANCHER_SERVICE_SEEDS
When using rancher, you may create two services to start a cluster. One of these
services would contain seed nodes. Therefore, instead of having to manually
list the IP addresses for the seed nodes, you can simply pass the rancher
service name and the image will auto-discover the IP addresses. You can also
pass multiple services (comma separated), and the first three ip addresses among
the services will be used as the seed nodes.


## License
See the license file.

## Contributors

* [Alejadnro Mesa](https://github.com/alejom99)
* [Gilman Callsen](https://github.com/callseng)
