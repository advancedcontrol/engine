
module Orchestrator
    module Api
        class StatsController < ApiController
            before_action :check_support
            before_action :set_period


            # Number of websocket connections (UI's / Users)
            def connections
                render json: {
                    period: @pname,
                    histogram: build_query(:connections_active)
                }
            end

            # Number of active important triggers
            def triggers
                render json: {
                    period: @pname,
                    histogram: build_query(:triggers_active)
                }
            end

            # Number of devices that were offline
            def offline
                render json: {
                    period: @pname,
                    histogram: build_query(:modules_disconnected)
                }
            end


            protected


            # Month
            #  Interval: 86400 (point for each day ~29 points)
            # Week
            #  Interval: 21600 (point for each quarter day ~28 points)
            # Day
            #  Interval: 1800 (30min intervals ~48 points)
            # Hour
            #  Interval: 300 (5min ~12 points)
            PERIODS = {
                month: [1.day.to_i,      proc { Time.now.to_i - 29.days.to_i }],
                week:  [6.hours.to_i,    proc { Time.now.to_i - 7.days.to_i  }],
                day:   [30.minutes.to_i, proc { Time.now.to_i - 1.day.to_i   }],
                hour:  [5.minutes.to_i,  proc { Time.now.to_i - 1.hour.to_i  }]
            }.freeze

            SAFE_PARAMS = [
                :period
            ].freeze

            def set_period
                args = params.permit(SAFE_PARAMS)
                @pname = (args[:period] || :day).to_sym
                @period = PERIODS[@pname]
            end


            def query
                {
                    filtered: {
                        query: {
                            bool: {
                                must: [{
                                    range: {
                                        stat_snapshot_at: {
                                            gte: @period[1].call
                                        }
                                    }
                                }]
                            }
                        },
                        filter: {
                            bool: {
                                must: [{
                                    type: {
                                        value: :stats
                                    }
                                }]
                            }
                        }
                    }
                }
            end

            def aggregation(field)
                {
                    field => {
                        histogram: {
                            min_doc_count: 0,
                            field: :stat_snapshot_at,
                            interval: @period[0]
                        },
                        aggregations: {
                            bucket_stats: {
                                stats: {
                                    field: field
                                }
                            }
                        }
                    }
                }
            end

            AGGS = 'aggregations'.freeze
            BUCKETS = 'buckets'.freeze
            BSTATS = 'bucket_stats'.freeze

            def build_query(field)
                ::Elastic.client.search({
                    index: ::Elastic::INDEX,
                    body: {
                        query: query,
                        size: 0,
                        aggregations: aggregation(field)
                    }
                })[AGGS][field.to_s][BUCKETS].collect { |b| b[BSTATS] }
            end
        end
    end
end
