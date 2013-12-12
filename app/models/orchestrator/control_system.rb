
module Orchestrator
    class ControlSystem < Couchbase::Model
        include ::CouchbaseId::Generator


        attr_accessor :running


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
        validates :settings,    presence: true
    end
end
