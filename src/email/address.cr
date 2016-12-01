class EMail::Address
  getter addr
  getter name

  # :nodoc:
  ADDRESS_FORMAT = /\A[a-zA-Z0-9\!\#\$\%\&\'\*\+\-\/\=\?\^\_\`^{\|\}\~]+(\.[a-zA-Z0-9\!\#\$\%\&\'\*\+\-\/\=\?\^\_\`^{\|\}\~]+)*@[a-zA-Z0-9\!\#\$\%\&\'\*\+\-\/\=\?\^\_\`^{\|\}\~]+(\.[a-zA-Z0-9\!\#\$\%\&\'\*\+\-\/\=\?\^\_\`^{\|\}\~]+)+\z/

  # :nodoc:
  NAME_FORMAT = /\A[a-zA-Z0-9\!\#\$\%\&\'\*\+\-\/\=\?\^\_\`\{\|\}\~ \t]+\z/

  def self.valid_address!(mail_address : ::String)
    raise Error::AddressError.new("#{mail_address.inspect} is invalid as a mail address.") unless mail_address =~ ADDRESS_FORMAT
    mail_address
  end

  def self.valid_name!(sender_name : ::String?)
    if sender_name
      raise Error::AddressError.new("#{sender_name.inspect} is invalid as a sender name") if sender_name =~ /[\r\n]/
    end
    sender_name
  end

  @addr : ::String
  @name : ::String? = nil

  def initialize(mail_address : ::String, sender_name : ::String? = nil)
    @addr = Address.valid_address!(mail_address)
    @name = Address.valid_name!(sender_name)
  end

  def to_s(io : IO)
    if sender_name = @name
      io << sender_name
      io << " <" << @addr << ">"
    else
      io << @addr
    end
  end
end
