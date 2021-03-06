# Changelog

## v0.8.0 (2018-03-26) 
* Added ability to override the following parameters in the cassandra.yml file:
 * trickle_fsync
 * trickle_fsync_interval_in_kb
 * write_request_timeout_in_ms
 * read_request_timeout_in_ms.

## v0.7.0 (2017-05-30)
* Added ability to override the following parameters in the cassandra.yaml file:
 * memtable_allocation_type
 * memtable_heap_space_in_mb
 * memtable_offheap_space_in_mb
* Bug fix to properly replace the values in the cassandra.yaml file using sed.

## v0.6.0 (2017-03-27)
* Added ability to override the following parameters in the cassandra.yaml file:
 * concurrent_reads
 * concurrent_writes
 * concurrent_counter_writes
 * concurrent_compactors
 * compaction_throughput_mb_per_sec
 * key_cache_size_in_mb
* Bug fix to copy the jmxremote.password from the jre to /etc/cassandra even
if JMX is not setup with Authentication.

## v0.5.0 (2017-01-10)
* Changed default version to Cassandra 2.2.5.
* Added configuration parameter CASSANDRA_ENABLE_G1GC to enable G1 GC.

## v0.4.3 (2016-09-01)
* Bug fix to treat config variables CASSANDRA_ENABLE_SSL,
CASSANDRA_ENABLE_JMX_AUTHENTICATION, CASSANDRA_ENABLE_JMX_SSL and
CASSANDRA_ENABLE_SSL_DEBUG as booleans.

## v0.4.2 (2016-08-15)
* Removed CRON service.
