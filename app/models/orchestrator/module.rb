require 'addressable/uri'


module Orchestrator
    class Module < Couchbase::Model
        include ::CouchbaseId::Generator


        # The classes / files that this module requires to execute
        # Defines module type
        belongs_to :dependency


        # Device module
        attribute :ip
        attribute :tls
        attribute :udp
        attribute :port
        attribute :makebreak,   default: false

        # HTTP Service module
        attribute :uri

        # Custom module names (in addition to what is defined in the dependency)
        attribute :priority,    default: 0
        attribute :settings,    default: lambda { {} }
        attribute :names,       default: lambda { [] }

        attribute :created_at,  default: lambda { Time.now.to_i }


        validates :makebreak,  presence: true
        validates :dependency, presence: true
        validate  :configuration


        protected


        def configuration
            if dependency.type == :device
                begin
                    url = Addressable::URI.parse("http://#{self.ip}:#{port}/")
                    url.scheme && url.host && url
                rescue
                    errors.add(:ip, 'ip, hostname or port are not valid')
                end
            elsif dependency.type == :service
                begin
                    url = Addressable::URI.parse(self.uri)
                    url.scheme && url.host && url
                rescue
                    errors.add(:uri, 'is an invalid URI')
                end
            end
        end
    end
end
