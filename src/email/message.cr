class EMail::Message
  @headers = {
    return_path:  Header::SingleAddress.new("Return-Path"),
    sender:       Header::SingleAddress.new("Sender"),
    from:         Header::AddressList.new("From"),
    reply_to:     Header::AddressList.new("Reply-To"),
    to:           Header::AddressList.new("To"),
    cc:           Header::AddressList.new("Cc"),
    bcc:          Header::AddressList.new("Bcc"),
    subject:      Header::Unstructured.new("Subject"),
    message_id:   Header::Unstructured.new("Message-Id"),
    date:         Header::Date.new,
    mime_version: Header::MimeVersion.new,
  }

  @body = Content::TextPlain.new
  @body_html = Content::TextHTML.new
  @body_resources = Hash(String, Content::AttachmentFile).new
  @attachments = Array(Content::AttachmentFile).new
  @envelope_from : Address? = nil

  def validate!
    raise Error::MessageError.new("Message has no subject.") if @headers[:subject].empty?
    raise Error::MessageError.new("Message has no From address.") if @headers[:from].empty?
    raise Error::MessageError.new("Message has no To addresses.") if @headers[:to].empty?
    raise Error::MessageError.new("Message has no contents.") if @body.empty? && @attachments.empty?
    raise Error::MessageError.new("Message has related resoures, but no text message") if message_has_resource? && !has_message?
    if @headers[:sender].empty? && @headers[:from].size > 1
      sender @headers[:from].list.first
    end
    if @headers[:return_path].empty?
      return_path @envelope_from || (@headers[:sender].empty? ? @headers[:from].list.first : @headers[:sender].addr)
    end
    self
  end

  def attach(file_path : String, file_name : String? = nil, mime_type : String? = nil)
    @attachments << Content::AttachmentFile.new(file_path, file_id: nil, file_name: file_name, mime_type: mime_type)
  end

  def attach(io : IO, file_name : String, mime_type : String? = nil)
    @attachments << Content::AttachmentFile.new(io, file_id: nil, file_name: file_name, mime_type: mime_type)
  end

  def message_resource(file_path : String, cid : String, file_name : String? = nil, mime_type : String? = nil)
    raise Error::MessageError.new("CID #{cid} already exists.") if @body_resources.has_key?(cid)
    @body_resources[cid] = Content::AttachmentFile.new(file_path, file_id: cid, file_name: file_name, mime_type: mime_type)
  end

  def message_resource(io : IO, cid : String, file_name : String, mime_type : String? = nil)
    raise Error::MessageError.new("CID #{cid} already exists.") if @body_resources.has_key?(cid)
    @body_resources[cid] = Content::AttachmentFile.new(io, file_id: cid, file_name: file_name, mime_type: mime_type)
  end

  def recipients
    @headers[:to].list + @headers[:cc].list + @headers[:bcc].list
  end

  def mail_from
    @envelope_from ||= @headers[:return_path].addr
  end

  def envelope_from(mail_address : String)
    @envelope_from = Address.new(mail_address)
  end

  def data
    to_s.gsub(/\r?\n/, "\r\n") + "\r\n.\r\n"
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
      raise Error::MessageError.new("Message doesn't have both of text and html message.")
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
    validate!
    @headers.each_value do |header|
      io << header << '\n' unless header.name == "Bcc" || header.empty?
    end
    io << body_content
  end

  def message(message_body : String)
    @body.message = message_body
  end

  def message_html(message_body : String)
    @body_html.message = message_body
  end

  # :nodoc:
  def date(timestamp : Time)
    @headers[:date].time = timestamp
  end

  macro set_text(header_type)
    def {{header_type.id}}(header_body : String)
      @headers[{{header_type}}].set(header_body)
    end
  end

  set_text :subject
  set_text :message_id

  macro set_address(header_type)
    def {{header_type.id}}(mail_address : String, sender_name : String? = nil)
      @headers[{{header_type}}].set(mail_address, sender_name)
    end

    def {{header_type.id}}(mail_address : Address)
      @headers[{{header_type}}].set(mail_address)
    end
  end

  set_address :sender
  set_address :return_path

  macro add_address(header_type)
    def {{header_type.id}}(mail_address : String, sender_name : String? = nil)
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
