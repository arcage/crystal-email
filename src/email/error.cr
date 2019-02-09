class EMail::Error < Exception
  class AddressError < Error; end

  class ContentError < Error; end

  class HeaderError < Error; end

  class ClientError < Error; end

  class ClientConfigError < Error; end

  class MessageError < Error; end

  class SenderError < Error; end
end
