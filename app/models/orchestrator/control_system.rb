require 'set'


module Orchestrator
    class ControlSystem < Couchbase::Model
        design_document :sys
        include ::CouchbaseId::Generator


        attribute :name
        attribute :description
        attribute :disabled     # prevents load on boot

        attribute :zones,       default: lambda { [] }
        attribute :modules,     default: lambda { [] }
        attribute :settings,    default: lambda { {} }

        attribute :created_at,  default: lambda { Time.now.to_i }


        # Zones and settings are only required for confident coding
        validates :name,        presence: true
        validates :zones,       presence: true
    end
end
