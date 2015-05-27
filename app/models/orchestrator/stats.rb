
module Orchestrator
    class Stats < Couchbase::Model

        # zzz so
        design_document :zzz
        include ::CouchbaseId::Generator

        # 29 days < couchbase basic TTL format limit
        TTL = Rails.env.production? ? 29.days.to_i : 1.day.to_i

        attribute :modules_disconnected, default: 0
        attribute :triggers_active,      default: 0
        attribute :connections_active,   default: 0

        attribute :created_at


        def initialize(*args)
            super(*args)

            query_for_stats
        end

        def save
            super(ttl: TTL)
        end


        protected


        @@accessing    ||= Elastic.new(::Orchestrator::AccessLog)        # Connections active
        @@triggers     ||= Elastic.new(::Orchestrator::TriggerInstance)  # Triggers active
        @@disconnected ||= Elastic.new(::Orchestrator::Module)           # Modules disconnected


        def query_for_stats
            self.created_at = Time.now.to_i
            self.id = "zzz_#{CLUSTER_ID}-#{self.created_at}"

            #----------------------
            # => Connections active
            #----------------------
            query = @@accessing.query
            query.missing(:ended_at)    # Still active
            query.raw_filter([{         # Model was updated in the last 2min
                range: {
                    last_checked_at: {
                        gte: self.created_at - 120
                    }
                }
            }])
            self.connections_active = @@accessing.count(query).to_i

            #-------------------
            # => Triggers active
            #-------------------
            query = @@triggers.query
            query.filter({
                triggered: [true],
                important: [true],
                enabled: [true]
            })
            self.triggers_active = @@triggers.count(query).to_i

            #------------------------
            # => Modules disconnected
            #------------------------
            query = @@disconnected.query
            query.filter({
                ignore_connected: [false],
                connected: [false],
                running: [true]
            })
            self.modules_disconnected = @@disconnected.count(query).to_i
        end
    end
end
