
# COMMON COMMANDS:


## Install ES Plugins

* Stop ElasticSearch if it is running
* Configure using `elasticsearch.yml`
* Install the following plugins:

```shell

./plugin -install mobz/elasticsearch-head
./plugin -install transport-couchbase -url http://packages.couchbase.com.s3.amazonaws.com/releases/elastic-search-adapter/2.0.0/elasticsearch-transport-couchbase-2.0.0.zip

```


## Update Configurations

* Start ElasticSearch
* Run the following commands (applying the template and creating the index `control`)

```shell

curl -X PUT http://localhost:9200/_template/couchbase -d @es_template.json
curl -X PUT http://localhost:9200/control/ -d '{"settings":{"number_of_shards":5,"number_of_replicas":1}}'
curl -X PUT http://localhost:9200/_template/couchbase -d @es_template.json

```
