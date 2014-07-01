#!/usr/bin/env bash

## paths relative to root of project
## ie: ./bin/ingest.sh

set -e 

RUN_DIR=$(pwd)
LOUVAIN_DIR=/srv/software/distributed-louvain-modularity/
printf "working dir $RUN_DIR\n"
printf "louvain dir $LOUVAIN_DIR\n"

if [ "$1" != "skip" ]; then 

    printf "ingest data\n"
    ./src/ingest_walker.py data/walker/output.csv

    printf "entity extraction\n"
    ./src/enrich_email_entities.py
fi

printf "entity rollup\n"
./src/enrich_rollup_entities.py

printf "enrich email comms\n"
./src/enrich_email_comms.py

if [ -e tmp/louvain.csv ]; then
    rm -f tmp/louvain.csv
fi

printf "create louvian input file\n"
./src/louvain_format.py -o tmp/ -f louvain.csv

if [ "$2" != "skip" ]; then 
    ### run louvain 

    #rebuild hdfs for newman
    if hadoop fs -test -d /tmp/newman; then
        hadoop fs -rm -r /tmp/newman
    fi

    hadoop fs -mkdir -p /tmp/newman/input
    hadoop fs -mkdir -p /tmp/newman/output

    hadoop fs -put tmp/louvain.csv /tmp/newman/input/

    if [ -e  $LOUVAIN_DIR/louvain.csv ]; then
        rm -f $LOUVAIN_DIR/louvain.csv
    fi

    # for louvain_to_gephi
    mv tmp/louvain.csv $LOUVAIN_DIR/louvain.csv

    ## kick off louvain
    cd $LOUVAIN_DIR
    python louvain.py /tmp/newman/input /tmp/newman/output

    if [ -d output ]; then
        rm -rf output
    fi

    hadoop fs -copyToLocal /tmp/newman/output .

    if [ -d louvain_to_gephi ]; then
        rm -rf louvain_to_gephi
    fi

    python louvain_to_gephi.py

    cd -

fi

printf "ingest louvain results\n"
./src/louvain_ingest_results.py $LOUVAIN_DIR/louvain_to_gephi/


printf "enrich email ranking\n"

if [ -e tmp/rankings ]; then
    rm -rf tmp/rankings
fi

if [ -e tmp/exploded.csv ]; then
    rm -rf tmp/exploded.csv
fi

./src/rank_ingest_results.py
./email_detector2.py kmrindfleisch@gmail.com > tmp/rankings
./src/rank_results.py
