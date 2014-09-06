
module Orchestrator
    class AccessLog < Couchbase::Model
        design_document :alog
        include ::CouchbaseId::Generator


        belongs_to :user,      class_name: "::User"
        attribute  :systems,   default: lambda { [] }

        attribute :persisted,  default: false
        attribute :suspected,  default: false
        attribute :notes

        attribute :created_at
        attribute :ended_at,   default: lambda { Time.now.to_i }


        def initialize
            super
            self.created_at = Time.now.to_i
        end

        def save
            if self.persisted
                super
            else
                super(ttl: 2.weeks.to_i)
            end
        end
    end
end
