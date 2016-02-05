
class User < Couchbase::Model
    # Mostly defined in coauth

    # Protected attributes
    attribute :sys_admin, default: false
    attribute :support,   default: false


    view :is_sys_admin
    def self.find_sys_admins
        is_sys_admin(key: true, stale: false)
    end
end
