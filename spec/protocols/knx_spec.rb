#encoding: ASCII-8BIT

require 'rails'
require 'protocols/knx'


describe "knx protocol helper" do
    before :each do
        @knx = Protocols::Knx.new
    end

    it "should parse and generate the same string" do
        datagram = @knx.read("\x06\x10\x05\x30\0\x11\x29\0\xbc\xe0\0\x01\x0a\0\x01\0\x80")
        expect(datagram.to_binary_s).to eq("\x06\x10\x05\x30\0\x11\x29\0\xbc\xe0\0\x01\x0a\0\x01\0\x80")

        datagram = @knx.read("\x06\x10\x05\x30\0\x11\x29\0\xbc\xe0\0\x01\x0a\0\x01\0\x81")
        expect(datagram.to_binary_s).to eq("\x06\x10\x05\x30\0\x11\x29\0\xbc\xe0\0\x01\x0a\0\x01\0\x81")
    end

    it "should generate appropriate group action requests" do
        datagram = @knx.action('1/2/0', false)
        expect(datagram.to_binary_s).to eq("\x06\x10\x05\x30\0\x11\x29\0\xbc\xe0\0\x01\x0a\0\x01\0\x80")

        datagram = @knx.action('1/2/0', true)
        expect(datagram.to_binary_s).to eq("\x06\x10\x05\x30\0\x11\x29\0\xbc\xe0\0\x01\x0a\0\x01\0\x81")
    end
end
