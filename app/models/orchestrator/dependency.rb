
module Orchestrator
    class Dependency < Couchbase::Model
        include ::CouchbaseId::Generator


        attribute :name
        attribute :description

        attribute :class_name
        attribute :module_names,    default: lambda { [] }
        attribute :settings,        default: lambda { {} }

        attribute :created_at,      default: lambda { Time.now.to_i }


        # Validations
        validates :name,            presence: true
        validates :class_name,      presence: true
        validates :module_names,    presence: true
    end
end
