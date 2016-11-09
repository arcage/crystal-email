
class EMail::Message

  @headers = {
    return_path: Header::SingleAddress.new("Return-Path"),
    sender:      Header::SingleAddress.new("Sender"),
    from:        Header::AddressList.new("From"),
    reply_to:    Header::AddressList.new("Reply-To"),
    to:          Header::AddressList.new("To"),
    cc:          Header::AddressList.new("Cc"),
    bcc:         Header::AddressList.new("Bcc"),
    subject:     Header::Unstructured.new("Subject"),
    message_id:  Header::Unstructured.new("Message-Id"),
    date:        Header::Date.new
  }
  @optional_headers = Hash(String, Array(Header)).new

  @body     = Content::TextPlain.new
  @attaches = [] of Content::AttachedFile
  @envelope_from : Address? = nil

  def validate!
    raise Error::InvalidMessage.new("Message has no from address.") if @headers[:from].empty?
    raise Error::InvalidMessage.new("Message has no recipient.") if recipients.empty?
    raise Error::InvalidMessage.new("Message has no content.") if @body.empty? && @attaches.empty?
    raise Error::InvalidMessage.new("Message has no subnect.") if @headers[:subject].empty?
    if @headers[:sender].empty? && @headers[:from].size > 1
      sender @headers[:from].list.first
    end
    if @headers[:return_path].empty?
      return_path @envelope_from || (@headers[:sender].empty? ? @headers[:from].list.first : @headers[:sender].addr)
    end
  end

  def attach(file_path : ::String, file_name : ::String? = nil, mime_type : ::String? = nil)
    @attaches << Content::AttachedFile.new(file_path, file_name, mime_type)
  end

  def attach(io : ::IO, file_name : ::String, mime_type : ::String? = nil)
    @attaches << Content::AttachedFile.new(io, file_name, mime_type)
  end

  def recipients
    @headers[:to].list + @headers[:cc].list + @headers[:bcc].list
  end

  def envelope_from
    @envelope_from ||= @headers[:return_path].addr
  end

  def envelope_from=(mail_address : ::String)
    @envelope_from = Address.new(mail_address)
  end

  def data
    to_s.gsub(/\r?\n/, "\r\n") + "\r\n.\r\n"
  end

  def to_s(io : IO)
    validate!
    @headers.each_value do |header|
      io << header  << "\n" unless header.name == "Bcc" || header.empty?
    end
    @optional_headers.each_value do |header_list|
      header_list.each do |header|
        io << header << "\n" unless header.empty?
      end
    end
    if @attaches.empty?
      @body.headers.each do |header|
        io << header << "\n" unless header.empty?
      end
      io << "\n"
      io << @body.data
    else
      boundary = "Multipart_Boundary_" + Time.now.epoch_ms.to_s + "--"
      io << Header::ContentTypeMultipartMixed.new(boundary) << "\n"
      io << Header::ContentTransferEncoding.new("7bit") << "\n"
      unless @body.empty?
        io << "\n--" << boundary << "\n"
        io << @body.data(with_header: true)
      end
      @attaches.each do |attached_file|
        io << "\n--" << boundary << "\n"
        io << attached_file.data(with_header: true)
      end
      io << "\n--" << boundary
    end
  end

  def message(message_body : ::String)
    @body.message = message_body
  end

  def date(timestamp : ::Time)
    @headers[:date].time = timestamp
  end

  macro set_unstructured(header_type)
    def {{header_type.id}}(header_body : ::String)
      @headers[{{header_type}}].set(header_body)
    end
  end

  set_unstructured :subject
  set_unstructured :message_id

  macro set_address(header_type)
    def {{header_type.id}}(mail_address : ::String, sender_name : ::String? = nil)
      @headers[{{header_type}}].set(mail_address, sender_name)
    end

    def {{header_type.id}}(mail_address : Address)
      @headers[{{header_type}}].set(mail_address)
    end
  end

  set_address :sender
  set_address :return_path

  macro add_address(header_type)
    def {{header_type.id}}(mail_address : ::String, sender_name : ::String? = nil)
      @headers[{{header_type}}].add(mail_address, sender_name)
    end

    def {{header_type.id}}(mail_address : Address)
      @headers[{{header_type}}].add(mail_address)
    end
  end

  add_address :from
  add_address :to
  add_address :cc
  add_address :bcc
  add_address :reply_to

end
