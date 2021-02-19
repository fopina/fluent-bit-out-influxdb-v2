#!/bin/sh

set -e

cd $(dirname $0)

function cleanup() {
        echo cleaning up
        docker rm -f test-fluent-plugin || true
}

docker run --rm \
           -v $(pwd):/myplugin fopina/fluent-bit-plugin-dev:v1.7.0-0 \
           sh -c "cmake -DFLB_SOURCE=/usr/src/fluentbit/fluent-bit-1.7.0/ \
                 -DPLUGIN_NAME=out_influxdb_v2 ../ && make"

cleanup
docker run --rm -p 8086 --name test-fluent-plugin -d quay.io/influxdb/influxdb:v2.0.3
trap "cleanup" EXIT
while [ 1 ]; do
        sleep 1
        echo "pinging influxd..."
        if docker exec test-fluent-plugin influx ping &> /dev/null; then
                echo "got response from influxd, proceeding"
                break
        fi
done

docker exec test-fluent-plugin influx setup \
                                      --force \
                                      --username admin \
                                      --password adminadmin \
                                      --org test \
                                      --bucket fluentbit \
                                      --token xxx

docker run --rm \
           -v $(pwd)/build:/myplugin \
           --link test-fluent-plugin:influxdb \
           fluent/fluent-bit:1.7.0 \
           /fluent-bit/bin/fluent-bit -v \
           -f 1 \
           -e /myplugin/flb-out_influxdb_v2.so \
           -i mem \
           -o influxdb_v2://influxdb/ -p org=test -p http_token=xxx -m '*' \
           -o exit -m '*'
