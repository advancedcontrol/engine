
class User < Couchbase::Model
    # Mostly defined in coauth

    # Protected attributes
    attribute :sys_admin, default: false
    attribute :support,   default: false
end
