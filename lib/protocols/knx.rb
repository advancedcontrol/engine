module Protocols; end


# == References
#
# https://github.com/lifeemotions/knx.net


class Protocols::Knx
    Datagram = Struct.new(*[
        :header_length,
        :protocol_version,
        :service_type,
        :total_length,

        # CONNECTION
        :channel_id,
        :status,

        # CEMI
        :message_code,
        :aditional_info_length,
        :aditional_info,
        :control_field_1,
        :control_field_2,
        :source_address,
        :destination_address,
        :data_length,
        :apdu,
        :data
    ])


    def initialize(local_address, local_port, logger, blk = nil, &block)
        @logger = logger

        @local_address = local_address.split('.').map(&:to_i)
        @local_port = local_port
        @channel_id = 0
        @sequence_number = 0

        @write_callback = blk || block
        @action_message_code = 0
        @three_level_group_addressing = true
    end

    attr_accessor :channel_id
    attr_accessor :action_message_code
    attr_accessor :three_level_group_addressing
    attr_reader :logger

    def on_event(blk = nil, &block)
        @event_callback = blk || block
    end

    def action(address, data)
        raw = case data.class
        when TrueClass, FalseClass
            [0, data ? 1 : 0]
        when String
            data.bytes
        when Fixnum
            data <= 255 ? [0, data] : [data & 0xFF, (data >> 8) & 0xFF]
        when Array
            # We assume this is a byte array
            data
        else
            raise "Unknown data type for #{data}"
        end

        @write_callback.call(create_action_datagram(address, data))
    end

    def request_status(address)
        @write_callback.call(create_status_datagram(address, data))
    end

    def process_response(data)
        datagram = Datagram.new
        datagram.header_length = data[0]
        datagram.protocol_version = data[1]
        datagram.service_type = [data[2], data[3]]
        datagram.total_length = data[4] + data[5]

        cemi = data[6..-1]

        process_cemi datagram, cemi
    end


    protected


    # ------------------------
    #    Response Processing
    # ------------------------
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

    def process_cemi(datagram, cemi)
        datagram.message_code = cemi[0]
        datagram.aditional_info_length = cemi[1]

        if datagram.aditional_info_length > 0
            datagram.aditional_info = cemi[2..datagram.aditional_info_length - 1]
        end

        datagram.control_field_1 = cemi[2 + datagram.aditional_info_length]
        datagram.control_field_1 = cemi[3 + datagram.aditional_info_length]

        datagram.source_address = get_individual_address([cemi[4 + datagram.aditional_info_length], cemi[5 + datagram.aditional_info_length]])
        datagram.destination_address = if get_destination_address_type(datagram.control_field_2) == :individual
            get_individual_address([cemi[6 + datagram.aditional_info_length], cemi[7 + datagram.aditional_info_length]])
        else
            get_group_address([cemi[6 + datagram.aditional_info_length], cemi[7 + datagram.aditional_info_length]])
        end

        datagram.data_length = cemi[8 + datagram.aditional_info_length]
        datagram.apdu = cemi[(8 + datagram.aditional_info_length)..datagram.data_length]

        datagram.data = get_data(datagram.data_length, datagram.apdu)

        logger.debug {
            "received #{datagram}"
        }

        return if datagram.message_code != 0x29

        type = datagram.apdu[1] >> 4
        @event_callback(datagram.destination_address, datagram.data)
    end


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
    def is_individual?(address)
        address.include? '.'
    end

    def is_group?(address)
        address.include? '/'
    end

    def invalid!(address)
        raise "invalid KNX address: #{address}"
    end

    def get_binary_address_of(address)
        group = is_group? address
        addr = [0, 0]

        # Extract address parts
        parts = if group
            address.split('/')
        else
            address.split('.')
        end
        three_level = parts.length == 3

        # Check if valid
        invalid = if group
            (parts.length != 3 || parts[0].length > 2 || parts[1].length > 1 || parts[2].length > 3) && (parts.length != 2 || parts[0].length > 2 || parts[1].length > 4)
        else
            parts.length != 3 || parts[0].length > 2 || parts[1].length > 2 || parts[2].length > 3
        end
        invalid!(address) if invalid

        # Build binary address
        if three_level
            part = parts[0].to_i
            invalid!(address) if part > 15
            addr[0] = (group ? (part << 3) : (part << 4)) & 0xFF

            part = parts[1].to_i
            invalid!(address) if (group && part > 7) || (!group && part > 15)
            addr[0] = (addr[0] | part) & 0xFF

            part = parts[2].to_i
            invalid!(address) if part > 255
            addr[1] = part
        else
            part = parts[0].to_i
            invalid!(address) if part > 15
            addr[0] = (part << 3) & 0xFF

            part = parts[1].to_i
            invalid!(address) if part > 2047

            part2 = [part].pack('n').unpack('cc')
            addr[0] = addr[0] | part2[0]
            addr[1] = part2[1]
        end

        addr
    end

    def get_human_readable(address, is_group:, is_three_level:)
        separator = is_group ? '/' : '.'
        addr = ''

        if is_group && !is_three_level
            # 2 level group
            addr << (address[0] >> 3).to_s
            addr << separator
            addr << (((address[0] & 0x07) << 8) + address[1]).to_s
        else
            # 3 level individual or group
            if is_group
                addr << ((address[0] & 0x7F) >> 3).to_s
                addr << separator
                addr << (address[0] & 0x07).to_s
            else
                addr << (address[0] >> 4).to_s
                addr << separator
                addr << (address[0] & 0x0F).to_s
            end

            addr << separator
            addr << address[1].to_s
        end

        addr
    end

    def get_individual_address(address)
        get_human_readable(address, is_group: false, is_three_level: false)
    end

    def get_group_address(address, three_level: true)
        get_human_readable(address, is_group: true, is_three_level: three_level)
    end



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

    KnxDestinationAddress = {
        individual: 0,
        group: 1
    }

    def get_destination_address_type(control_field_2)
        if (0x80 & control_field_2) == 0
            :individual
        else
            :group
        end
    end



    # ---------------------
    #    Data Processing
    # ---------------------

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

    def get_data(length, apdu)
        case length
        when 0
            ''
        when 1
            ('' << (0x3F & apdu[1]))
        when 2
            ('' << apdu[2])
        else
            array_to_str apdu[2..-1]
        end
    end

    def get_data_length(data)
        return 0 if data.length <= 0
        return 1 if data.length == 1 && data[0] < 0x3F
        return data.length if data[0] < 0x3F
        return data.length + 1
    end

    def write_data(datagram:, data_start:, data:)
        if data.length == 1
            if data[0] < 0x3F
                datagram[data_start] = datagram[data_start] | data[0]
            else
                datagram[data_start + 1] = data[0]
            end
        elsif data.length > 1
            if data[0] < 0x3F
                datagram[data_start] = datagram[data_start] | data[0]
                data[1..-1].each_with_index do |val, i|
                    datagram[data_start + i + 1] = val
                end
            else
                data.each_with_index do |val, i|
                    datagram[data_start + i + 1] = val
                end
            end
        end
    end


    # ------------------
    #    Service Type
    # ------------------

    KnxServiceType = {
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
        routing_lost_message: 0x0531,
        unknown: 0
    }

    def get_service_type(datagram)
        type = case datagram[2]
        when 0x02
            case datagram[3]
            when 0x06
                KnxServiceType[:connect_response]
            when 0x09
                KnxServiceType[:disconnect_request]
            when 0x08
                KnxServiceType[:connectionstate_response]
            end
        when 0x04
            case datagram[3]
            when 0x20
                KnxServiceType[:tunnelling_request]
            when 0x21
                KnxServiceType[:tunnelling_ack]
            end
        end

        return type || KnxServiceType[:unknown]
    end



    # ------------------
    #    Datagrams
    # ------------------

    # CEMI (start at position 6)
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

    def create_action_datagram_common(destination_address, data, header)
        data_length = get_data_length(data)
        datagram = Array.new(data_length + 10 + header.length, 0)
        header.each_with_index { |val, i| datagram[i] = val }

        len = header.length
        datagram[len] = @action_message_code != 0x00 ? @action_message_code : 0x11
        datagram[len + 1] = 0x00
        datagram[len + 2] = 0xAC

        datagram[len + 3] = is_individual?(destination_address) ? 0x50 : 0xF0

        datagram[len + 4] = 0x00
        datagram[len + 5] = 0x00

        dst_address = get_binary_address_of(destination_address)
        datagram[len + 6] = dst_address[0]
        datagram[len + 7] = dst_address[1]
        datagram[len + 8] = data_length

        datagram[len + 9] = 0x00
        datagram[len + 10] = 0x80

        write_data(datagram: datagram, data_start: len + 10, data: data)
        datagram
    end

    def create_status_datagram_common(destination_address, datagram, cemi_start_pos)
        datagram[cemi_start_pos] = @action_message_code != 0x00 ? @action_message_code : 0x11

        datagram[cemi_start_pos + 1] = 0x00
        datagram[cemi_start_pos + 2] = 0xAC

        datagram[cemi_start_pos + 3] = is_individual?(destination_address) ? 0x50 : 0xF0

        datagram[cemi_start_pos + 4] = 0x00
        datagram[cemi_start_pos + 5] = 0x00

        dst_address = get_binary_address_of(destination_address)
        datagram[cemi_start_pos + 6] = dst_address[0]
        datagram[cemi_start_pos + 7] = dst_address[1]

        datagram[cemi_start_pos + 8] = 0x01
        datagram[cemi_start_pos + 9] = 0x00
        datagram[cemi_start_pos + 10] = 0x00

        datagram
    end

    # These are currently the router version
    def create_action_datagram(destination_address, data)
        data_length = get_data_length(data)

        # HEADER
        datagram = Array.new(6, 0)
        datagram[0] = 0x06
        datagram[1] = 0x10
        datagram[2] = 0x05
        datagram[3] = 0x30

        total_length = [data_length + 16].pack('n').unpack('cc')
        datagram[4] = total_length[1]
        datagram[5] = total_length[0]

        create_action_datagram_common(destination_address, data, datagram)
    end

    def create_status_datagram(destination_address)
        datagram = Array.new(6, 0)
        datagram[00] = 0x06
        datagram[01] = 0x10
        datagram[02] = 0x05
        datagram[03] = 0x30
        datagram[04] = 0x00
        datagram[05] = 0x11

        create_status_datagram_common(destination_address, datagram, 6);
    end
end
