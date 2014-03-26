require 'digest'

module Orchestrator
    class TrustedDevice < Couchbase::Model
        design_document :trust
        include ::CouchbaseId::Generator


        # TODO:: first confirmation prevents the trust from dissolving automatically
        #  so we don't have failed trusts (due to network or whatever) sitting in the DB
        # before_create :sunset_first_confirm


        # The user this device belongs to
        belongs_to :user

        # One time key used to validate the user
        attribute :current_secret
        attribute :previous_secret

        attribute :created_at,      default: lambda { Time.now.to_i }
        attribute :last_accessed,   default: lambda { Time.now.to_i }

        # TODO:: expiration using ttl to remove keys automatically
        #attribute :expires
        #def set_expiration(date? or From now?)


        # Once the user has saved the new key we remove the old
        # Two phase commit
        def update_confirmed
            TrustedDevice.bucket.delete("trustkey-#{previous_secret}", {quiet: true})
            previous_secret = nil
            save!
        end

        # Rotates the keys
        def update_secret
            old_prev = previous_secret
            previous_secret = current_secret
            current_secret = Digest::SHA1.hexdigest((Time.now.to_f / (1 + rand(100))).to_s)
            last_accessed = Time.now.to_i
            save!
            TrustedDevice.bucket.delete("trustkey-#{old_prev}", {quiet: true}) unless previous_secret.nil?
            TrustedDevice.bucket.set("trustkey-#{current_secret}", self.id)
        end

        # remove trust
        def remove
            TrustedDevice.bucket.delete("trustkey-#{previous_secret}", {quiet: true}) unless previous_secret.nil?
            TrustedDevice.bucket.delete("trustkey-#{current_secret}", {quiet: true})
            self.delete
        end


        protected


        validates :user,            presence: true
        validates :current_secret,  presence: true
    end
end
