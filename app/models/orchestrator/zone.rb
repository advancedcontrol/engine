
module Orchestrator
    class Zone < Couchbase::Model
        design_document :zone
        include ::CouchbaseId::Generator


        attribute :name
        attribute :description
        attribute :settings,    default: lambda { {} }
        attribute :groups,      default: lambda { [] }

        attribute :created_at,  default: lambda { Time.now.to_i }


        validates :name,  presence: true
    end
end
