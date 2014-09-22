# Cent OS - Control Setup

Database Server:

* Couchbase
* ElasticSearch


Control Server:

* git
* Python 2.x
* Libcouchbase
* RVM
* Ruby
* nginx




## Database Server Setup

* Install couchbase (http://docs.couchbase.com/couchbase-manual-2.5/cb-install/)
    * `sudo yum install -y pkgconfig`
    * `yum install openssl098e`
    * Download rpm to the server
    * `rpm –install couchbase-server version.rpm`
* Configure Couchbase Limits
    * `vim /etc/security/limits.conf` and add:

```
couchbase hard nofile 10240
couchbase hard core unlimited
```

* Install Elastic Search
    * http://www.elasticsearch.org/guide/en/elasticsearch/reference/current/setup-service.html
    * Install Elastic Search Head: https://github.com/mobz/elasticsearch-head
    * Install Couchbase plugin: http://docs.couchbase.com/couchbase-elastic-search/
    * Edit elastic search config - add cluster name
    * Configure ES Mappings with `es_template.json`
* Configure XDCR (Couchbase -> ElasticSearch)


## Control Server Setup

* Install Git + Python
    * `sudo yum install git`
    * `sudo yum install python2`
    * `sudo yum install python2-devel`
* Install Deps
    * `sudo yum install gcc g++ make automake autoconf curl-devel openssl-devel zlib-devel httpd-devel apr-devel apr-util-devel sqlite-devel`
    * `yum install -y rubygem-nokogiri`
    * Libcouchbase: http://www.couchbase.com/communities/c-client-library
* Install Ruby
    * `sudo curl -sSL https://get.rvm.io | bash`
    * `rvm reload`
    * `rvm list known`
    * `rvm install 2.1`
* Configure Proxies
    * sudo vi /etc/subversion/servers

```
[Global]
http-proxy-host=web-cache.usyd.edu.au
http-proxy-port=8080
```

* Configure Env Variables
  * `sudo vim /etc/environment`

```
HTTP_PROXY=http://web-cache.usyd.edu.au:8080/
NO_PROXY="localhost, 127.0.0.1, *.sydney.edu.au, *.usyd.edu.au, 172.*.*.*, 10.*.*.*"
COUCHBASE_HOST=COUCH-DB-UAT-1.UCC.USYD.EDU.AU
COUCHBASE_PORT=8091
COUCHBASE_PASSWORD=password here
COUCHBASE_BUCKET=control
COUCHBASE_POOL=default
ELASTIC=COUCH-DB-UAT-1.UCC.USYD.EDU.AU
ELASTIC_INDEX=control
```

* Configure nginx
    * See nginx.conf
    * `sudo mv ./nginx.conf /etc/nginx/nginx.conf`
    * Start at boot `chkconfig nginx on`
    * Might need to manually configure run levels
        * `chkconfig` to see if nginx is configured to run
        * `chkconfig --level 3 nginx on`
        * Repeat for levels 4 and 5
    * Start service `service start nginx`
* Install ACA Engine
    * `cd /home`
    * `mkdir aca_apps`
    * `git clone git clone https://bitbucket.org/william_le/engine-starter-kit.git`
    * `git clone https://stakach@bitbucket.org/quaypay/coauth.git`
    * `git clone https://stakach@bitbucket.org/quaypay/coauth.git`
    * `git clone https://stakach@bitbucket.org/aca/control.git`
    * `mv ./engine-starter-kit ./sydney-control`
    * `cd sydney-control`
    * `gem install bundler`
    * `bundle install`
* Start ACA Engine on boot
    * See acaengine.sh
    * `sudo mv ./acaengine.sh /etc/init.d/acaengine`
    * Make executable `chmod +x /etc/init.d/acaengine`
    * Start at boot `chkconfig acaengine on`
    * Start service `service start acaengine`
