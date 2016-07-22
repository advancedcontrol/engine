#encoding: ASCII-8BIT

module Protocols; end


require 'bindata'


class Protocols::KnxObjectServer
    class KnxHeader < BinData::Record
        endian :big

        uint8  :header_length,  value: 0x06   # Length 6
        uint8  :version,        value: 0x20
        uint16 :request_type,   value: 0xF080 # ObjectServer
        uint16 :request_length
    end

    class ConnectionHeader < BinData::Record
        endian :big

        uint8  :header_length,  value: 0x04
        uint8  :reserved1,      value: 0x00
        uint8  :reserved2,      value: 0x00
        uint8  :reserved3,      value: 0x00
    end


    Filters = {
        0 => :all_values,
        1 => :valid_values,
        2 => :updated_values
    }
    Filters.merge!(Filters.invert)

    class ObjectHeader < BinData::Record
        endian :big

        uint8  :main_service, value: 0xF0
        uint8  :sub_service
        uint16 :start_item
        uint16 :item_count

        attr_accessor :filter

        def to_binary_s
            resp = super()
            resp << @filter if @filter
            resp
        end
    end

    Status = {
        0 => :idle_ok,
        1 => :idle_error,
        2 => :transmission_in_progress,
        3 => :transmission_request
    }

    class StatusItem < BinData::Record
        endian :big

        uint16 :id

        bit3   :reserved
        bit1   :valid
        bit1   :update_from_bus
        bit1   :data_request
        bit2   :status

        uint8  :value_length


        attr_accessor :value


        def to_binary_s
            self.value_length = @value ? @value.length : 0
            "#{super()}#{@value}"
        end

        def transmission_status
            ::Protocols::KnxObjectServer::Status[self.status]
        end
    end


    Commands = {
        0 => :no_command,
        1 => :set_value,
        2 => :send_value,
        3 => :set_value_and_send,
        4 => :read_value,
        5 => :clear_transmission_state
    }
    Commands.merge!(Commands.invert)

    class RequestItem < BinData::Record
        endian :big

        uint16 :id
        bit4   :reserved
        bit4   :command
        uint8  :value_length


        attr_accessor :value


        def to_binary_s
            self.value_length = @value ? @value.length : 0
            "#{super()}#{@value}"
        end
    end


    Errors = {
        0 => :no_error,
        1 => :device_internal_error,
        2 => :no_item_found,
        3 => :buffer_is_too_small,
        4 => :item_not_writeable,
        5 => :service_not_supported,
        6 => :bad_service_param,
        7 => :wrong_datapoint_id,
        8 => :bad_datapoint_command,
        9 => :bad_datapoint_length,
        10 => :message_inconsistent,
        11 => :object_server_busy
    }


    Datagram = Struct.new(:knx_header, :connection, :header) do
        def initialize(raw_data = nil)
            super(KnxHeader.new, ConnectionHeader.new, ObjectHeader.new)
            @data = []

            if raw_data
                self.knx_header.read(raw_data[0..5])
                self.connection.read(raw_data[6..9])
                self.header.read(raw_data[10..15])

                # Check for error
                if self.header.item_count == 0
                    @error_code = raw_data[16].getbyte(0)
                    @error = Errors[@error_code]
                else
                    @error_code = 0
                    @error = :no_error

                    # Read the response
                    index = 16
                    self.header.item_count.times do
                        next_index = index + 4
                        item = StatusItem.new
                        item.read(raw_data[index...next_index])

                        index = next_index + item.value_length
                        item.value = raw_data[next_index...index]

                        @data << item
                    end
                end
            end
        end


        attr_reader :error, :error_code, :data


        def error?
            @error_code != 0
        end

        def to_binary_s
            self.header.item_count = @data.length if @data.length > 0
            resp = "#{self.connection.to_binary_s}#{self.header.to_binary_s}"

            @data.each do |item|
                resp << item.to_binary_s
            end

            self.knx_header.request_length = resp.length + 6
            "#{self.knx_header.to_binary_s}#{resp}"
        end

        def add_action(index, data: nil, **options)
            req = RequestItem.new
            req.id = index.to_i
            req.command = Commands[options[:command]] || :set_value
            if not data.nil?
                if data == true || data == false
                    data = data ? 1 : 0
                end

                if data.is_a? String
                    req.value = data
                else
                    req.value = ''
                    req.value << data
                end
            end
            @data << req
            self
        end
    end


    # ===========================
    #   Object Server Interface
    # ===========================
    # Usage:
    #
    #   knx = Protocols::KnxObjectServer.new
    #   req = knx.action(1, data: true)
    #   send req.to_binary_s
    #
    
    Defaults = {
        filter: :valid_values,
        item_count: 1,
        command: :set_value_and_send
    }

    def initialize(options = {})
        @options = Defaults.merge(options)
    end

    def action(index, data: nil, **options)
        options = @options.merge(options)

        cmd = Datagram.new
        cmd.add_action(index, data: data, **options)
        cmd.header.sub_service = 0x06
        cmd.header.start_item = index
        cmd
    end

    def status(index, options = {})
        options = @options.merge(options)

        data = Datagram.new
        data.header.sub_service = 0x05
        data.header.start_item = index.to_i
        data.header.item_count = options[:item_count].to_i
        data.header.filter = Filters[options[:filter]]
        data
    end

    def read(raw_data)
        Datagram.new(raw_data)
    end
end
