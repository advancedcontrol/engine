#encoding: ASCII-8BIT

module Protocols; end

# == References
#
# https://github.com/lifeemotions/knx.net


require 'bindata'


class Protocols::Knx

    # http://www.openremote.org/display/forums/KNX+IP+Connection+Headers
    class Header < BinData::Record
        endian :big

        uint8  :header_length,  value: 0x06  # Length 6 (always for version 1)
        uint8  :version,        value: 0x10  # Version 1
        uint16 :request_type
        uint16 :request_length
    end

    RequestTypes = {
        search_request: 0x0201,
        search_response: 0x0202,
        description_request: 0x0203,
        description_response: 0x0204,
        connect_request: 0x0205,
        connect_response: 0x0206,
        connectionstate_request: 0x0207,
        connectionstate_response: 0x0208,
        disconnect_request: 0x0209,
        disconnect_response: 0x020A,
        device_configuration_request: 0x0310,
        device_configuration_ack: 0x0311,
        tunnelling_request: 0x0420,
        tunnelling_ack: 0x0421,
        routing_indication: 0x0530,
        routing_lost_message: 0x0531
    }


    # CEMI
    # +--------+--------+--------+--------+----------------+----------------+--------+----------------+
    # |  Msg   |Add.Info| Ctrl 1 | Ctrl 2 | Source Address | Dest. Address  |  Data  |      APDU      |
    # | Code   | Length |        |        |                |                | Length |                |
    # +--------+--------+--------+--------+----------------+----------------+--------+----------------+
    #   1 byte   1 byte   1 byte   1 byte      2 bytes          2 bytes       1 byte      2 bytes
    #
    #  Message Code    = 0x11 - a L_Data.req primitive
    #      COMMON EMI MESSAGE CODES FOR DATA LINK LAYER PRIMITIVES
    #          FROM NETWORK LAYER TO DATA LINK LAYER
    #          +---------------------------+--------------+-------------------------+---------------------+------------------+
    #          | Data Link Layer Primitive | Message Code | Data Link Layer Service | Service Description | Common EMI Frame |
    #          +---------------------------+--------------+-------------------------+---------------------+------------------+
    #          |        L_Raw.req          |    0x10      |                         |                     |                  |
    #          +---------------------------+--------------+-------------------------+---------------------+------------------+
    #          |                           |              |                         | Primitive used for  | Sample Common    |
    #          |        L_Data.req         |    0x11      |      Data Service       | transmitting a data | EMI frame        |
    #          |                           |              |                         | frame               |                  |
    #          +---------------------------+--------------+-------------------------+---------------------+------------------+
    #          |        L_Poll_Data.req    |    0x13      |    Poll Data Service    |                     |                  |
    #          +---------------------------+--------------+-------------------------+---------------------+------------------+
    #          |        L_Raw.req          |    0x10      |                         |                     |                  |
    #          +---------------------------+--------------+-------------------------+---------------------+------------------+
    #          FROM DATA LINK LAYER TO NETWORK LAYER
    #          +---------------------------+--------------+-------------------------+---------------------+
    #          | Data Link Layer Primitive | Message Code | Data Link Layer Service | Service Description |
    #          +---------------------------+--------------+-------------------------+---------------------+
    #          |        L_Poll_Data.con    |    0x25      |    Poll Data Service    |                     |
    #          +---------------------------+--------------+-------------------------+---------------------+
    #          |                           |              |                         | Primitive used for  |
    #          |        L_Data.ind         |    0x29      |      Data Service       | receiving a data    |
    #          |                           |              |                         | frame               |
    #          +---------------------------+--------------+-------------------------+---------------------+
    #          |        L_Busmon.ind       |    0x2B      |   Bus Monitor Service   |                     |
    #          +---------------------------+--------------+-------------------------+---------------------+
    #          |        L_Raw.ind          |    0x2D      |                         |                     |
    #          +---------------------------+--------------+-------------------------+---------------------+
    #          |                           |              |                         | Primitive used for  |
    #          |                           |              |                         | local confirmation  |
    #          |        L_Data.con         |    0x2E      |      Data Service       | that a frame was    |
    #          |                           |              |                         | sent (does not mean |
    #          |                           |              |                         | successful receive) |
    #          +---------------------------+--------------+-------------------------+---------------------+
    #          |        L_Raw.con          |    0x2F      |                         |                     |
    #          +---------------------------+--------------+-------------------------+---------------------+

    #  Add.Info Length = 0x00 - no additional info
    #  Control Field 1 = see the bit structure above
    #  Control Field 2 = see the bit structure above
    #  Source Address  = 0x0000 - filled in by router/gateway with its source address which is
    #                    part of the KNX subnet
    #  Dest. Address   = KNX group or individual address (2 byte)
    #  Data Length     = Number of bytes of data in the APDU excluding the TPCI/APCI bits
    #  APDU            = Application Protocol Data Unit - the actual payload including transport
    #                    protocol control information (TPCI), application protocol control
    #                    information (APCI) and data passed as an argument from higher layers of
    #                    the KNX communication stack
    #
    class CEMI < BinData::Record
        endian :big
        
        uint8 :msg_code
        uint8 :info_length


        # ---------------------
        #    Control Fields
        # ---------------------

        # Bit order
        # +---+---+---+---+---+---+---+---+
        # | 7 | 6 | 5 | 4 | 3 | 2 | 1 | 0 |
        # +---+---+---+---+---+---+---+---+

        #  Control Field 1

        #   Bit  |
        #  ------+---------------------------------------------------------------
        #    7   | Frame Type  - 0x0 for extended frame
        #        |               0x1 for standard frame
        #  ------+---------------------------------------------------------------
        #    6   | Reserved
        #        |
        #  ------+---------------------------------------------------------------
        #    5   | Repeat Flag - 0x0 repeat frame on medium in case of an error
        #        |               0x1 do not repeat
        #  ------+---------------------------------------------------------------
        #    4   | System Broadcast - 0x0 system broadcast
        #        |                    0x1 broadcast
        #  ------+---------------------------------------------------------------
        #    3   | Priority    - 0x0 system
        #        |               0x1 normal (also called alarm priority)
        #  ------+               0x2 urgent (also called high priority)
        #    2   |               0x3 low
        #        |
        #  ------+---------------------------------------------------------------
        #    1   | Acknowledge Request - 0x0 no ACK requested
        #        | (L_Data.req)          0x1 ACK requested
        #  ------+---------------------------------------------------------------
        #    0   | Confirm      - 0x0 no error
        #        | (L_Data.con) - 0x1 error
        #  ------+---------------------------------------------------------------
        bit1  :is_standard_frame
        bit1  :_reserved_,   value: 0
        bit1  :no_repeat
        bit1  :broadcast
        bit2  :priority     # 2 bits
        bit1  :ack_requested
        bit1  :is_error

        #  Control Field 2

        #   Bit  |
        #  ------+---------------------------------------------------------------
        #    7   | Destination Address Type - 0x0 individual address
        #        |                          - 0x1 group address
        #  ------+---------------------------------------------------------------
        #   6-4  | Hop Count (0-7)
        #  ------+---------------------------------------------------------------
        #   3-0  | Extended Frame Format - 0x0 standard frame
        #  ------+---------------------------------------------------------------
        bit1  :is_group_address
        bit3  :hop_count
        bit4  :extended_frame_format

        uint16 :source_address
        uint16 :destination_address

        uint8 :data_length


        # In the Common EMI frame, the APDU payload is defined as follows:

        # +--------+--------+--------+--------+--------+
        # | TPCI + | APCI + |  Data  |  Data  |  Data  |
        # |  APCI  |  Data  |        |        |        |
        # +--------+--------+--------+--------+--------+
        #   byte 1   byte 2  byte 3     ...     byte 16

        # For data that is 6 bits or less in length, only the first two bytes are used in a Common EMI
        # frame. Common EMI frame also carries the information of the expected length of the Protocol
        # Data Unit (PDU). Data payload can be at most 14 bytes long.  <p>

        # The first byte is a combination of transport layer control information (TPCI) and application
        # layer control information (APCI). First 6 bits are dedicated for TPCI while the two least
        # significant bits of first byte hold the two most significant bits of APCI field, as follows:

        #   Bit 1    Bit 2    Bit 3    Bit 4    Bit 5    Bit 6    Bit 7    Bit 8      Bit 1   Bit 2
        # +--------+--------+--------+--------+--------+--------+--------+--------++--------+----....
        # |        |        |        |        |        |        |        |        ||        |
        # |  TPCI  |  TPCI  |  TPCI  |  TPCI  |  TPCI  |  TPCI  | APCI   |  APCI  ||  APCI  |
        # |        |        |        |        |        |        |(bit 1) |(bit 2) ||(bit 3) |
        # +--------+--------+--------+--------+--------+--------+--------+--------++--------+----....
        # +                            B  Y  T  E    1                            ||       B Y T E  2
        # +-----------------------------------------------------------------------++-------------....

        # Total number of APCI control bits can be either 4 or 10. The second byte bit structure is as follows:

        #   Bit 1    Bit 2    Bit 3    Bit 4    Bit 5    Bit 6    Bit 7    Bit 8      Bit 1   Bit 2
        # +--------+--------+--------+--------+--------+--------+--------+--------++--------+----....
        # |        |        |        |        |        |        |        |        ||        |
        # |  APCI  |  APCI  | APCI/  |  APCI/ |  APCI/ |  APCI/ | APCI/  |  APCI/ ||  Data  |  Data
        # |(bit 3) |(bit 4) | Data   |  Data  |  Data  |  Data  | Data   |  Data  ||        |
        # +--------+--------+--------+--------+--------+--------+--------+--------++--------+----....
        # +                            B  Y  T  E    2                            ||       B Y T E  3
        # +-----------------------------------------------------------------------++-------------....
        bit2 :tpci # transport protocol control information
        bit4 :tpci_seq_num # Sequence number when tpci is sequenced
        bit4 :apci # application protocol control information (What we trying to do: Read, write, respond etc)
        bit6 :data # Or the tail end of APCI depending on the message type
    end

    # APCI type
    ActionType = {
        group_read:  0,
        group_resp:  1,
        group_write: 2,

        individual_write: 3,
        individual_read:  4,
        individual_resp:  5,

        adc_read: 6,
        adc_resp: 7,

        memory_read:  8,
        memory_resp:  9,
        memory_write: 10,

        user_msg: 11,

        descriptor_read: 12,
        descriptor_resp: 13,

        restart: 14,
        escape:  15
    }

    TpciType = {
        unnumbered_data: 0b00,
        numbered_data:   0b01,
        unnumbered_control: 0b10,
        numbered_control:   0b11
    }

    MsgCode = {
        send_datagram: 0x29
    }

    Priority = {
        system: 0,
        alarm: 1,
        high: 2,
        low: 3
    }


    # ------------------------
    #    Address Processing
    # ------------------------
    #           +-----------------------------------------------+
    # 16 bits   |              INDIVIDUAL ADDRESS               |
    #           +-----------------------+-----------------------+
    #           | OCTET 0 (high byte)   |  OCTET 1 (low byte)   |
    #           +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
    #    bits   | 7| 6| 5| 4| 3| 2| 1| 0| 7| 6| 5| 4| 3| 2| 1| 0|
    #           +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
    #           |  Subnetwork Address   |                       |
    #           +-----------+-----------+     Device Address    |
    #           |(Area Adrs)|(Line Adrs)|                       |
    #           +-----------------------+-----------------------+

    #           +-----------------------------------------------+
    # 16 bits   |             GROUP ADDRESS (3 level)           |
    #           +-----------------------+-----------------------+
    #           | OCTET 0 (high byte)   |  OCTET 1 (low byte)   |
    #           +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
    #    bits   | 7| 6| 5| 4| 3| 2| 1| 0| 7| 6| 5| 4| 3| 2| 1| 0|
    #           +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
    #           |  | Main Grp  | Midd G |       Sub Group       |
    #           +--+--------------------+-----------------------+

    #           +-----------------------------------------------+
    # 16 bits   |             GROUP ADDRESS (2 level)           |
    #           +-----------------------+-----------------------+
    #           | OCTET 0 (high byte)   |  OCTET 1 (low byte)   |
    #           +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
    #    bits   | 7| 6| 5| 4| 3| 2| 1| 0| 7| 6| 5| 4| 3| 2| 1| 0|
    #           +--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+--+
    #           |  | Main Grp  |            Sub Group           |
    #           +--+--------------------+-----------------------+
    module Address
        module ClassMethods
            def parse(input)
                address = @address_class.new
                klass = input.class

                if klass == Array
                    address.read(input.pack('n'))
                elsif [Integer, Fixnum].include? klass
                    address.read([input].pack('n'))
                elsif klass == String
                    tmp = parse_friendly(input)
                    if tmp.nil?
                        address.read(input)
                    else
                        address = tmp
                    end
                else
                    raise 'address parsing failed'
                end

                address
            end
        end

        def self.included(base)
            base.instance_variable_set(:@address_class, base)
            base.extend(ClassMethods)
        end

        def to_i
            # 16-bit unsigned, network (big-endian)
            to_binary_s.unpack('n')[0]
        end

        def is_group?; true; end
    end

    class GroupAddress < ::BinData::Record
        include Address
        endian :big

        bit1 :_reserved_,   value: 0
        bit4 :main_group
        bit3 :middle_group
        uint8 :sub_group
        

        def to_s
            "#{main_group}/#{middle_group}/#{sub_group}"
        end

        def self.parse_friendly(str)
            result = str.split('/')
            if result.length == 3
                address = GroupAddress.new
                address.main_group   = result[0].to_i
                address.middle_group = result[1].to_i
                address.sub_group    = result[2].to_i
                address
            end
        end
    end

    class GroupAddress2Level < ::BinData::Record
        include Address
        endian :big

        bit1  :_reserved_,   value: 0
        bit4  :main_group
        bit11 :sub_group
        

        def to_s
            "#{main_group}/#{sub_group}"
        end

        def self.parse_friendly(str)
            result = str.split('/')
            if result.length == 2
                address = GroupAddress2Level.new
                address.main_group = result[0].to_i
                address.sub_group = result[1].to_i
                address
            end
        end
    end

    class IndividualAddress < ::BinData::Record
        include Address
        endian :big

        bit4 :area_address
        bit4 :line_address
        uint8 :device_address
        
        def to_s
            "#{area_address}.#{line_address}.#{device_address}"
        end

        def is_group?; false; end

        def self.parse_friendly(str)
            result = str.split('.')
            if result.length == 3
                address = IndividualAddress.new
                address.area_address = result[0].to_i
                address.line_address = result[1].to_i
                address.device_address = result[2].to_i
            end
        end
    end
    # ------------------------
    #  End Address Processing
    # ------------------------


    DatagramBuilder = Struct.new(:header, :cemi, :source_address, :destination_address, :data) do

        def to_binary_s
            data_array = self.data

            resp = if data_array.present?
                @cemi.data_length = data_array.length

                if data_array[0] <= 0b111111
                    @cemi.data = data_array[0]
                    if data_array.length > 1
                        data_array[1..-1].pack('C')
                    else
                        String.new
                    end
                else
                    @cemi.data = 0
                    data_array.pack('C')
                end
            else
                @cemi.data = 0
                @cemi.data_length = 0
                String.new
            end

            @cemi.source_address      = self.source_address.to_i
            @cemi.destination_address = self.destination_address.to_i

            # 17 == header + cemi
            @header.request_length = resp.bytesize + 17
            "#{@header.to_binary_s}#{@cemi.to_binary_s}#{resp}"
        end


        protected


        def initialize(address = nil, options = nil)
            super()
            return unless address

            @address = parse(address)

            @cemi = CEMI.new
            @cemi.msg_code = MsgCode[options[:msg_code]]
            @cemi.is_standard_frame = true
            @cemi.no_repeat = options[:no_repeat]
            @cemi.broadcast = options[:broadcast]
            @cemi.priority = Priority[options[:priority]]

            @cemi.is_group_address = @address.is_group?
            @cemi.hop_count = options[:hop_count]

            @header = Header.new
            if options[:request_type]
                @header.request_type = RequestTypes[options[:request_type]]
            else
                @header.request_type = RequestTypes[:routing_indication]
            end

            self.header = @header
            self.cemi = @cemi
            self.source_address = IndividualAddress.parse_friendly('0.0.1')
            self.destination_address = @address

            @cemi.source_address      = self.source_address.to_i
            @cemi.destination_address = self.destination_address.to_i
        end

        def parse(address)
            result = address.split('/')
            if result.length > 1
                if result.length == 3
                    GroupAddress.parse_friendly(address)
                else
                    GroupAddress2Level.parse_friendly(address)
                end
            else
                IndividualAddress.parse_friendly(address)
            end
        end
    end

    class ActionDatagram < DatagramBuilder
        def initialize(address, data_array, options)
            super(address, options)

            # Set the protocol control information
            @cemi.apci = @address.is_group? ? ActionType[:group_write] : ActionType[:individual_write]
            @cemi.tpci = TpciType[:unnumbered_data]

            # To attempt save a byte we try to cram the first byte into the APCI field
            if data_array.present?
                if data_array[0] <= 0b111111
                    @cemi.data = data_array[0]
                end
                
                @cemi.data_length = data_array.length
                self.data = data_array
            end
        end
    end

    class StatusDatagram < DatagramBuilder
        def initialize(address, options)
            super(address, options)

            # Set the protocol control information
            @cemi.apci = @address.is_group? ? ActionType[:group_read] : ActionType[:individual_read]
            @cemi.tpci = TpciType[:unnumbered_data]
        end
    end

    class ResponseDatagram < DatagramBuilder
        def initialize(raw_data, options)
            super()

            @header = Header.new
            @header.read(raw_data[0..5])

            @cemi = CEMI.new
            @cemi.read(raw_data[6..16])

            self.header = @header
            self.cemi = @cemi

            self.data = raw_data[17..(@header.request_length - 1)].bytes
            if @cemi.data_length > self.data.length
                self.data.unshift @cemi.data
            end

            self.source_address = IndividualAddress.parse(@cemi.source_address.to_i)

            if @cemi.is_group_address == 0
                self.destination_address = IndividualAddress.parse(@cemi.destination_address.to_i)
            elsif options[:two_level_group]
                self.destination_address = GroupAddress2Level.parse(@cemi.destination_address.to_i)
            else
                self.destination_address = GroupAddress.parse(@cemi.destination_address.to_i)
            end
        end
    end



    # ==========================
    #   KNX Protocol Interface
    # ==========================
    # Usage:
    #
    #   knx = Protocols::Knx.new
    #   req = knx.action('1/2/0', true)
    #   send req.to_binary_s
    #

    Defaults = {
        priority: :low,
        no_repeat: true,
        broadcast: true,
        hop_count: 6,
        msg_code: :send_datagram
    }

    def initialize(options = {})
        @options = Defaults.merge(options)
    end

    def action(address, data, options = {})
        if data == true || data == false
            data = data ? 1 : 0
        end

        klass = data.class

        raw = if klass == String
            data.bytes
        elsif [Integer, Fixnum].include? klass
            # Assume this is a byte
            [data]
        elsif klass == Array
            # We assume this is a byte array
            data
        else
            raise "Unknown data type for #{data}"
        end

        ActionDatagram.new(address, raw, @options.merge(options))
    end


    def status(address, options = {})
        StatusDatagram.new(address, @options.merge(options))
    end

    def read(data, options = {})
        ResponseDatagram.new(data, @options.merge(options))
    end
end
