# :nodoc:
class EMail::Address
  # email address
  getter addr
  # mailbox name
  getter name

  # :nodoc:
  ADDRESS_FORMAT = /\A[a-zA-Z0-9\!\#\$\%\&\'\*\+\-\/\=\?\^\_\`^{\|\}\~]+(\.[a-zA-Z0-9\!\#\$\%\&\'\*\+\-\/\=\?\^\_\`^{\|\}\~]+)*@[a-zA-Z0-9\!\#\$\%\&\'\*\+\-\/\=\?\^\_\`^{\|\}\~]+(\.[a-zA-Z0-9\!\#\$\%\&\'\*\+\-\/\=\?\^\_\`^{\|\}\~]+)+\z/

  # :nodoc:
  NAME_FORMAT = /\A[a-zA-Z0-9\!\#\$\%\&\'\*\+\-\/\=\?\^\_\`\{\|\}\~ \t]+\z/

  # raise `EMail::Error::AddressError` when the given email address is invalid.
  def self.valid_address!(mail_address : String)
    raise EMail::Error::AddressError.new("#{mail_address.inspect} is invalid as a mail address.") unless mail_address =~ ADDRESS_FORMAT
    mail_address
  end

  # raise `EMail::Error::AddressError` when the given mailbox name is invalid.
  def self.valid_name!(mailbox_name : String?)
    if mailbox_name
      raise EMail::Error::AddressError.new("#{mailbox_name.inspect} is invalid as a sender name") if mailbox_name =~ /[\r\n]/
    end
    mailbox_name
  end

  @addr : String
  @name : String? = nil

  def initialize(mail_address : String, mailbox_name : String? = nil)
    @addr = Address.valid_address!(mail_address)
    @name = Address.valid_name!(mailbox_name)
  end

  def to_s(io : IO)
    if mailbox_name = @name
      io << (mailbox_name =~ Header::FIELD_BODY ? mailbox_name : Header::ENCODE_DEFINITION_HEAD + Base64.strict_encode(mailbox_name.to_slice) + Header::ENCODE_DEFINITION_TAIL)
      io << " <" << @addr << '>'
    else
      io << @addr
    end
  end
end
