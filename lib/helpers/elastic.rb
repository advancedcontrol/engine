require 'elasticsearch'

class Elastic
    class Query
        def initialize(params)
            query = params.permit(:q, :limit, :offset)

            @filters = nil
            @search = query[:q]

            @limit = query[:limit] || 20
            @limit = @limit.to_i
            @limit = 50 if @limit > 50

            @offset = query[:offset] || 0
            @offset = offset.to_i
            @offset = 10000 if offset > 10000
        end


        attr_accessor :offset
        attr_accessor :limit
        attr_accessor :sort

        def raw_filter(filter)
            @raw_filter = filter
        end


        # filters is in the form {fieldname1: ['var1','var2',...], fieldname2: ['var1','var2'...]}
        # NOTE:: may overwrite an existing filter in merge
        def filter(filters)
            @filters ||= {}
            @filters.merge!(filters)
        end

        # Like filter however all keys are OR's instead of AND's
        def or_filter(filters)
            @orFilter ||= {}
            @orFilter.merge!(filters)
        end

        def range(filter)
            @rangeFilter ||= []
            @rangeFilter << filter
        end

        # Call to add fields that should be missing
        # Effectively adds a filter that ensures a field is missing
        def missing(*fields)
            @missing ||= Set.new
            @missing.merge(fields)
        end

        # The opposite of filter
        def not(filters)
            @nots ||= {}
            @nots.merge!(filters)
        end

        def build
            if @filters
                fieldfilters = []

                @filters.each do |key, value|
                    fieldfilter = { :or => [] }
                    build_filter(fieldfilter[:or], key, value)

                    # TODO:: Discuss this - might be a security issue
                    unless fieldfilter[:or].empty?
                        fieldfilters.push(fieldfilter)
                    end
                end
            end

            if @orFilter
                fieldfilters ||= []
                fieldfilter = { :or => [] }
                orArray = fieldfilter[:or]

                @orFilter.each do |key, value|
                    build_filter(orArray, key, value)
                end

                unless orArray.empty?
                    fieldfilters.push(fieldfilter)
                end
            end

            if @rangeFilter
                fieldfilters ||= []

                @rangeFilter.each do |value|
                    fieldfilters.push({range: value})
                end
            end

            if @nots
                fieldfilters ||= []

                @nots.each do |key, value|
                    fieldfilter = { :not => { :or => [] } }
                    build_filter(fieldfilter[:not][:or], key, value)
                    unless fieldfilter[:not].empty?
                        fieldfilters.push(fieldfilter)
                    end
                end
            end

            if @missing
                fieldfilters ||= []

                @missing.each do |field|
                    fieldfilters.push({
                        missing: { field: field }
                    })
                end
            end

            if @raw_filter
                fieldfilters = @raw_filter
            end

            if @search.present?
                # HACK:: This is such a hack.
                # TODO:: join('* ') + '*' (i.e fix ES tokeniser and then match start of words)
                {
                    query: {
                        query_string: {
                            query: '*' + @search.scan(/[a-zA-Z0-9]+/).join('* *') + '*'
                        }
                    },
                    filters: fieldfilters,
                    offset: @offset,
                    limit: @limit
                }
            else
                {
                    sort: @sort || [{created_at: 'desc'}],
                    filters: fieldfilters,
                    query: {
                        match_all: {}
                    },
                    offset: @offset,
                    limit: @limit
                }
            end
        end


        #protected


        def build_filter(filters, key, values)
            values.each { |var|
                if var.nil?
                    filters.push({
                        missing: { field: key }
                    })
                else
                    filters.push({
                        :term => {
                            key => var
                        }
                    })
                end
            }
        end
    end


    HOST = if ENV['ELASTIC']
        ENV['ELASTIC'].split(' ').map {|item| "#{item}:9200"}
    else
        ['localhost:9200']
    end

    @@client ||= Elasticsearch::Client.new hosts: HOST, reload_connections: true
    def self.search *args
        @@client.search *args
    end

    HITS = 'hits'.freeze
    TOTAL = 'total'.freeze
    ID = '_id'.freeze
    SCORE = '_score'.freeze
    INDEX = (ENV['ELASTIC_INDEX'] || 'default').freeze

    def initialize(klass, index = INDEX)
        @klass = klass
        @filter = klass.design_document
        @index = index
    end

    # Safely build the query
    def query(params, filters = nil)
        builder = ::Elastic::Query.new(params)
        builder.filter(filters) if filters
        builder
    end

    def search(builder, &block)
        opt = builder.build

        sort = opt[:sort] || []
        sort << SCORE

        queries = opt[:queries] || []
        queries.unshift(opt[:query])

        filters = opt[:filters] || []
        filters.unshift({term: {type: @filter}})

        query = {
            index: @index,
            body: {
                sort: sort,
                query: {
                    filtered: {
                        query: {
                            bool: {
                                must: queries
                            }
                        },
                        filter: {
                            bool: {
                                must: filters
                            }
                        }
                    }
                },
                from: opt[:offset],
                size: opt[:limit]
            }
        }

        # if a formatter block is supplied, each loaded record is passed to it
        # allowing annotation/conversion of records using data from the model
        # and current request (e.g groups are annotated with 'admin' if the
        # currently logged in user is an admin of the group)
        result = Elastic.search(query)
        records = @klass.find_by_id(result[HITS][HITS].map {|entry| entry[ID]}) || []
        {
            total: result[HITS][TOTAL] || 0,
            results: block_given? ? records.map {|record| yield record} : records
        }
    end
end
