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
        

        # filters is in the form {fieldname1: ['var1','var2',...], fieldname2: ['var1,',var2'...]}
        # NOTE:: may overwrite an existing filter in merge
        def filter(filters)
            @filters ||= {}
            @filters.merge!(filters)
        end

        # Call to add fields that should be missing
        # Effectively adds a filter that ensures a field is missing
        def missing(*fields)
            @missing ||= Set.new
            @missing.merge(fields)
        end

        def build
            if @filters
                fieldfilters = []

                @filters.each do |key, value|
                    fieldfilter = { :or => [] }
                        value.each { |var|
                            if var
                                fieldfilter[:or].push({
                                    :term => {
                                        key => var
                                    }
                                })
                            else
                                fieldfilter[:or].push({
                                    missing: { field: field }
                                })
                            end
                        }
                    fieldfilters.push(fieldfilter)
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
    ID = '_id'.freeze
    SCORE = '_score'.freeze
    INDEX = (ENV['ELASTIC_INDEX'] || 'default').freeze

    def initialize(filter, index = INDEX)
        @filter = filter
        @index = index
    end

    # Safely build the query
    def query(params, filters = nil)
        builder = ::Elastic::Query.new(params)
        builder.filter(filters) if filters
        builder
    end

    def search(builder)
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

        Elastic.search(query)[HITS][HITS].map {|entry| entry[ID]}
    end
end
