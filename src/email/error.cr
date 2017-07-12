class EMail::Error < Exception
  class AddressError < Error; end

  class ContentError < Error; end

  class HeaderError < Error; end

  class ClientError < Error; end

  class MessageError < Error; end

  class DupulicateCidError < Error; end
end
