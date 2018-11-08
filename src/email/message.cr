class EMail::Message
  @preset_headers = {
    return_path: Header::SingleAddress.new("Return-Path"),
    sender:      Header::SingleAddress.new("Sender"),
    from:        Header::AddressList.new("From"),
    reply_to:    Header::AddressList.new("Reply-To"),
    to:          Header::AddressList.new("To"),
    cc:          Header::AddressList.new("Cc"),
    bcc:         Header::AddressList.new("Bcc"),
    subject:     Header::Unstructured.new("Subject"),
    message_id:  Header::Unstructured.new("Message-Id"),
    date:        Header::Date.new,
  }

  @custom_headers = Array(Header::Unstructured).new

  @body = Content::TextContent.new("plain")
  @body_html = Content::TextContent.new("html")
  @body_resources = Hash(String, Content::AttachmentFile).new
  @attachments = Array(Content::AttachmentFile).new
  @envelope_from : Address? = nil

  def validate!
    raise EMail::Error::MessageError.new("Message has no subject.") if @preset_headers[:subject].empty?
    raise EMail::Error::MessageError.new("Message has no From address.") if @preset_headers[:from].empty?
    raise EMail::Error::MessageError.new("Message has no To addresses.") if @preset_headers[:to].empty?
    raise EMail::Error::MessageError.new("Message has no contents.") if @body.empty? && @body_html.empty? && @attachments.empty?
    raise EMail::Error::MessageError.new("Message has related resoures, but no text message") if message_has_resource? && !has_message?
    if @preset_headers[:sender].empty? && @preset_headers[:from].size > 1
      sender @preset_headers[:from].list.first
    end
    if @preset_headers[:return_path].empty?
      return_path @envelope_from || (@preset_headers[:sender].empty? ? @preset_headers[:from].list.first : @preset_headers[:sender].addr)
    end
    self
  end

  def recipients
    @preset_headers[:to].list + @preset_headers[:cc].list + @preset_headers[:bcc].list
  end

  def mail_from
    @envelope_from ||= @preset_headers[:return_path].addr
  end

  def envelope_from(mail_address : String)
    @envelope_from = Address.new(mail_address)
  end

  def data
    to_s.gsub(/\r?\n/, "\r\n").gsub(/\r\n\./, "\r\n..") + "\r\n.\r\n"
  end

  def has_text_message?
    !@body.empty?
  end

  def has_html_message?
    !@body_html.empty?
  end

  def has_message?
    has_text_message? || has_html_message?
  end

  def message_has_resource?
    !@body_resources.empty?
  end

  def has_multipart_message?
    has_text_message? && has_html_message?
  end

  def has_attache?
    !@attachments.empty?
  end

  def content_count
    count = has_message? ? 1 : 0
    count += @attachments.size
    count
  end

  def has_multipart_body?
    content_count > 1
  end

  def message_text_content
    if has_multipart_message?
      Content::Multipart.new("alternative") << @body << @body_html
    elsif has_text_message?
      @body
    elsif has_html_message?
      @body_html
    else
      raise EMail::Error::MessageError.new("Message doesn't have both of text and html message.")
    end
  end

  def message_content
    if message_has_resource?
      content = Content::Multipart.new("related")
      content << message_text_content
      @body_resources.each_value do |resource|
        content << resource
      end
      content
    else
      message_text_content
    end
  end

  def body_content
    if has_multipart_body?
      content = Content::Multipart.new("mixed")
      content << message_content if has_message?
      @attachments.each do |attachment|
        content << attachment
      end
      content
    else
      if has_attache?
        @attachments.first
      else
        message_content
      end
    end
  end

  def to_s(io : IO)
    @preset_headers.each_value do |header|
      io << header << '\n' unless header.name == "Bcc" || header.empty?
    end
    @custom_headers.each do |header|
      io << header << '\n'
    end
    io << Header::MimeVersion.new << '\n'
    io << body_content
  end

  def message(message_body : String)
    @body.data = message_body
  end

  def message_html(message_body : String)
    @body_html.data = message_body
  end

  def attach(file_path : String, file_name : String? = nil, mime_type : String? = nil)
    @attachments << Content::AttachmentFile.new(file_path, file_id: nil, file_name: file_name, mime_type: mime_type)
  end

  def attach(io : IO, file_name : String, mime_type : String? = nil)
    @attachments << Content::AttachmentFile.new(io, file_id: nil, file_name: file_name, mime_type: mime_type)
  end

  def message_resource(file_path : String, cid : String, file_name : String? = nil, mime_type : String? = nil)
    raise EMail::Error::MessageError.new("CID #{cid} already exists.") if @body_resources.has_key?(cid)
    @body_resources[cid] = Content::AttachmentFile.new(file_path, file_id: cid, file_name: file_name, mime_type: mime_type)
  end

  def message_resource(io : IO, cid : String, file_name : String, mime_type : String? = nil)
    raise EMail::Error::MessageError.new("CID #{cid} already exists.") if @body_resources.has_key?(cid)
    @body_resources[cid] = Content::AttachmentFile.new(io, file_id: cid, file_name: file_name, mime_type: mime_type)
  end

  def custom_header(name : String, value : String)
    normalized_name = name.downcase.gsub('-', '_')
    raise Error::MessageError.new("Mime-Version header is automatically set to 1.0, and cannot be overwritten.") if normalized_name == "mime_version"
    raise Error::MessageError.new("#{name} header must be set by using ##{normalized_name} method") if @preset_headers.keys.map(&.to_s).includes?(normalized_name)
    opt_hdr = Header::Unstructured.new(name.to_s)
    opt_hdr.set(value)
    @custom_headers << opt_hdr
  end

  # :nodoc:
  def date(timestamp : Time)
    @preset_headers[:date].time = timestamp
  end

  macro set_text(header_type)
    def {{header_type.id}}(header_body : String)
      @preset_headers[{{header_type}}].set(header_body)
    end
  end

  set_text :subject
  set_text :message_id

  macro set_address(header_type)
    def {{header_type.id}}(mail_address : String, sender_name : String? = nil)
      @preset_headers[{{header_type}}].set(mail_address, sender_name)
    end

    def {{header_type.id}}(mail_address : Address)
      @preset_headers[{{header_type}}].set(mail_address)
    end
  end

  set_address :sender
  set_address :return_path

  macro add_address(header_type)
    def {{header_type.id}}(mail_address : String, sender_name : String? = nil)
      @preset_headers[{{header_type}}].add(mail_address, sender_name)
    end

    def {{header_type.id}}(mail_address : Address)
      @preset_headers[{{header_type}}].add(mail_address)
    end
  end

  add_address :from
  add_address :to
  add_address :cc
  add_address :bcc
  add_address :repry_to
end
