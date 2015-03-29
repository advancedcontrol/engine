
module Orchestrator
    class EdgeControl < Couchbase::Model
        design_document :edge
        include ::CouchbaseId::Generator


        attribute :name
        attribute :description
        attribute :failover
        attribute :timeout,     default: 30
        attribute :window_start   # CRON string
        attribute :window_length  # Time in seconds
        attribute :settings,    default: lambda { {} }
        attribute :admins,      default: lambda { [] }
        attribute :commit         # Current commit

        attribute :created_at,  default: lambda { Time.now.to_i }


        def online?(id)
            
        end
    end
end
