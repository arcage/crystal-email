# Email message object.
#
# ### Minimal email with plain text message.
#
# ```
# email = EMail::Message.new
#
# # Email headers
# email.from "your_addr@example.com"
# email.to "to@example.com"
# email.subject "Subject of the mail"
#
# # Email plain text email body
# email.message <<-EOM
#   Message body of the mail.
#
#   --
#   Your Signature
#   EOM
# ```
#
# You can set following preset headers and your own `#custom_header`s:
#
# - **[*][!]** `#from`
# - **[*][?]** `#to`
# - **[*][?]** `#cc`
# - **[*][?]** `#bcc`
# - **[*]** `#reply_to`
# - `#return_path`
# - `#sender`
# - `#envelope_from`
# - **[!]** `#subject`
#
# **[!]** required.
#
# **[*]** callable multiple times.
#
# **[?]** required at least one of these recipients.
#
# ### Add multiple email addresses at once
#
# For **From**, **To**, **Cc**, **Bcc**, and **Reply-To** headers, you can add multiple email addresses at once with array of **String** or **EMail::Address**.
#
# ```
# # Add two email addresses with array of email address strings
# email.to ["to1@example.com", "to2@example.com"]
#
# # Notice: Following code will not add two email addresses
# #         but only one email address "to1@example.com"
# #         that has mailbox name "to2@example.com"
# email.to "to1@example.com", "to2@example.com"
# ```
#
# or
#
# ```
# # Add two email addresses with array of EMail::Address ojects
# addr_list = [] of EMail::Address
# addr_list << EMail::Address.new("to1@example.com", "to1 name")
# addr_list << EMail::Address.new("to2@example.com", "to2 name")
# email.to addr_list
# ```
#
# ### Set custom header
#
# ```
# email.custom_header "X-Mailer", "Your APP Name"
# ```
# ### Set mailbox name with email address
#
# ```
# email.from "your_addr@example.com", "your name"
# ```
#
# Also, `#to`, `#cc`, `#bcc`, etc...
#
# ### HTML email with altanative plain text message.
#
# ```
# email = EMail::Message.new
#
# # Email headers
# email.from "your_addr@example.com"
# email.to "to@example.com"
# email.subject "Subject of the mail"
#
# # Email plain text email body
# email.message <<-EOM
#   Message body of the mail.
#
#   --
#   Your Signature
#   EOM
#
# # Email HTML email body
# email.message_html <<-EOM
#   <html>
#   <body>
#   <h1>Subject of the mail<h1>
#   <p>Message body of the mail.</p>
#   <footer>
#   Your Signature
#   </footer>
#   </body>
#   </html>
#   EOM
# ```
#
# ### Attache files
#
# ```
# email = EMail::Message.new
#
# # Email headers
# email.from "your_addr@example.com"
# email.to "to@example.com"
# email.subject "Subject of the mail"
#
# # Email plain text email body
# email.message <<-EOM
#   Message body of the mail.
#
#   --
#   Your Signature
#   EOM
#
# # Attach file to email
# email.attach "./photo.jpeg"
# ```
#
# #### Set alternative file name for recipient
#
# ```
# email.attach "./photo.jpeg", file_name: "last_year.jpeg"
# ```
#
# #### Set specific MIME type
#
# ```
# email.attach "./data", mime_type: "text/csv"
# ```
#
# #### Read attachment file data from IO
#
# ```
# email.attach io, file_name: "photo.jpeg"
# ```
# In this case, `file_name` argument is required.
#
# ### Add message resouces
#
# ```
# email = EMail::Message.new
#
# # Email headers
# email.from "your_addr@example.com"
# email.to "to@example.com"
# email.subject "Subject of the mail"
#
# # Email plain text email body
# email.message <<-EOM
#   Message body of the mail.
#
#   --
#   Your Signature
#   EOM
#
# # Email HTML email body
# email.message_html <<-EOM
#   <html>
#   <body>
#   <img src="cid:logo@some.domain">
#   <h1>Subject of the mail<h1>
#   <p>Message body of the mail.</p>
#   <footer>
#   Your Signature
#   </footer>
#   </body>
#   </html>
#   EOM
#
# # Add message resource
# email.message_resource "./logo.png", cid: "logo@some.domain"
# ```
#
# `#message_resource` is lmost same as `#attach` expect it requires `cid` argument.
class NetUtils::EMail::Message
  @preset_headers = {
    return_path: EMail::Header::SingleAddress.new("Return-Path"),
    sender:      EMail::Header::SingleAddress.new("Sender"),
    from:        EMail::Header::AddressList.new("From"),
    reply_to:    EMail::Header::AddressList.new("Reply-To"),
    to:          EMail::Header::AddressList.new("To"),
    cc:          EMail::Header::AddressList.new("Cc"),
    bcc:         EMail::Header::AddressList.new("Bcc"),
    subject:     EMail::Header::Unstructured.new("Subject"),
    message_id:  EMail::Header::Unstructured.new("Message-Id"),
    date:        EMail::Header::Date.new,
  }

  @custom_headers = Array(EMail::Header::Unstructured).new

  @body = EMail::Content::TextContent.new("plain")
  @body_html = EMail::Content::TextContent.new("html")
  @body_resources = Hash(String, EMail::Content::AttachmentFile).new
  @attachments = Array(EMail::Content::AttachmentFile).new
  @envelope_from : EMail::Address? = nil

  # :nodoc:
  def validate!
    raise EMail::MessageError.new("Message has no subject.") if @preset_headers[:subject].empty?
    raise EMail::MessageError.new("Message has no From address.") if @preset_headers[:from].empty?
    raise EMail::MessageError.new("Message has no To addresses.") if @preset_headers[:to].empty?
    raise EMail::MessageError.new("Message has no contents.") if @body.empty? && @body_html.empty? && @attachments.empty?
    raise EMail::MessageError.new("Message has related resoures, but no text message") if message_has_resource? && !has_message?
    if @preset_headers[:sender].empty? && @preset_headers[:from].size > 1
      sender @preset_headers[:from].list.first
    end
    if @preset_headers[:return_path].empty?
      return_path @envelope_from || (@preset_headers[:sender].empty? ? @preset_headers[:from].list.first : @preset_headers[:sender].addr)
    end
    self
  end

  # :nodoc:
  def recipients
    @preset_headers[:to].list + @preset_headers[:cc].list + @preset_headers[:bcc].list
  end

  # :nodoc:
  def mail_from
    @envelope_from ||= @preset_headers[:return_path].addr
  end

  # Set envelope from address.
  def envelope_from(mail_address : String)
    @envelope_from = Address.new(mail_address)
  end

  # :nodoc:
  def data
    to_s.gsub(/\r?\n/, "\r\n").gsub(/\r\n\./, "\r\n..") + "\r\n.\r\n"
  end

  # :nodoc:
  def has_text_message?
    !@body.empty?
  end

  # :nodoc:
  def has_html_message?
    !@body_html.empty?
  end

  # :nodoc:
  def has_message?
    has_text_message? || has_html_message?
  end

  # :nodoc:
  def message_has_resource?
    !@body_resources.empty?
  end

  # :nodoc:
  def has_multipart_message?
    has_text_message? && has_html_message?
  end

  # :nodoc:
  def has_attache?
    !@attachments.empty?
  end

  # :nodoc:
  def content_count
    count = has_message? ? 1 : 0
    count += @attachments.size
    count
  end

  # :nodoc:
  def has_multipart_body?
    content_count > 1
  end

  # :nodoc:
  def message_text_content
    if has_multipart_message?
      EMail::Content::Multipart.new("alternative") << @body << @body_html
    elsif has_text_message?
      @body
    elsif has_html_message?
      @body_html
    else
      raise EMail::MessageError.new("Message doesn't have both of text and html message.")
    end
  end

  # :nodoc:
  def message_content
    if message_has_resource?
      content = EMail::Content::Multipart.new("related")
      content << message_text_content
      @body_resources.each_value do |resource|
        content << resource
      end
      content
    else
      message_text_content
    end
  end

  # :nodoc:
  def body_content
    if has_multipart_body?
      content = EMail::Content::Multipart.new("mixed")
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
    io << EMail::Header::MimeVersion.new << '\n'
    io << body_content
  end

  # Sets plain text message body.
  def message(message_body : String)
    @body.data = message_body
  end

  # Sets html text message body.
  def message_html(message_body : String)
    @body_html.data = message_body
  end

  # Attaches the file from given file path.
  #
  # You can set another `file_name` for recipients and sprcific `mime_type`.
  # By default, MIME type will be inferred from extname of the file name.
  def attach(file_path : String, file_name : String? = nil, mime_type : String? = nil)
    @attachments << Content::AttachmentFile.new(file_path, file_id: nil, file_name: file_name, mime_type: mime_type)
  end

  # Attaches the file read from given IO.
  #
  # In this case, `file_name` argument is required.
  def attach(io : IO, file_name : String, mime_type : String? = nil)
    @attachments << Content::AttachmentFile.new(io, file_id: nil, file_name: file_name, mime_type: mime_type)
  end

  # Adds message resource file, such as images or stylesheets for the html message, from given file path.
  #
  # Almost same as `#attach` expect this require `cid` argument.
  def message_resource(file_path : String, cid : String, file_name : String? = nil, mime_type : String? = nil)
    raise EMail::MessageError.new("CID #{cid} already exists.") if @body_resources.has_key?(cid)
    @body_resources[cid] = EMail::Content::AttachmentFile.new(file_path, file_id: cid, file_name: file_name, mime_type: mime_type)
  end

  # Adds message resource file, such as images or stylesheets for the html message, read from given IO.
  #
  # Almost same as `#attach` expect this require `cid` argument.
  def message_resource(io : IO, cid : String, file_name : String, mime_type : String? = nil)
    raise EMail::MessageError.new("CID #{cid} already exists.") if @body_resources.has_key?(cid)
    @body_resources[cid] = EMail::Content::AttachmentFile.new(io, file_id: cid, file_name: file_name, mime_type: mime_type)
  end

  # Sets cuntome header you want to set to the message.
  def custom_header(name : String, value : String)
    normalized_name = name.downcase.gsub('-', '_')
    raise EMail::MessageError.new("Mime-Version header is automatically set to 1.0, and cannot be overwritten.") if normalized_name == "mime_version"
    raise EMail::MessageError.new("#{name} header must be set by using ##{normalized_name} method") if @preset_headers.keys.map(&.to_s).includes?(normalized_name)
    opt_hdr = EMail::Header::Unstructured.new(name)
    opt_hdr.set(value)
    @custom_headers << opt_hdr
  end

  # Removes all custom headers with specific name.
  def clear_custom_header(name : String)
    normalized_name = Header.normalize_name(name)
    @custom_headers.reject! { |opt_hdr| opt_hdr.name == normalized_name }
  end

  # :nodoc:
  def date(timestamp : Time)
    @preset_headers[:date].time = timestamp
  end

  # :nodoc:
  macro set_text(header_type)
    # Set **{{header_type.id.split("_").map(&.capitalize).join("-").id}}** header.
    def {{header_type.id}}(header_body : String)
      @preset_headers[{{header_type}}].set(header_body)
    end
  end

  set_text :subject
  set_text :message_id

  # :nodoc:
  macro set_address(header_type)
    # Sets email address to **{{header_type.id.split("_").map(&.capitalize).join("-").id}}** header.
    def {{header_type.id}}(mail_address : String, mailbox_name : String? = nil)
      @preset_headers[{{header_type}}].set(mail_address, mailbox_name)
    end

    # :ditto:
    def {{header_type.id}}(mail_address : EMail::Address)
      @preset_headers[{{header_type}}].set(mail_address)
    end
  end

  set_address :sender
  set_address :return_path

  # :nodoc:
  macro add_address(header_type)
    # Adds email address to **{{header_type.id.split("_").map(&.capitalize).join("-").id}}** header.
    #
    # Call this multiple times to set multiple addresses.
    def {{header_type.id}}(mail_address : String, mailbox_name : String? = nil)
      @preset_headers[{{header_type}}].add(mail_address, mailbox_name)
    end
  
    # :ditto:
    def {{header_type.id}}(mail_address : EMail::Address)
      @preset_headers[{{header_type}}].add(mail_address)
    end

    # Adds multiple email addresses to **{{header_type.id.split("_").map(&.capitalize).join("-").id}}** header at once.
    #
    # In this method, you cannot set mailbox name.
    def {{header_type.id}}(mail_addresses : Array(String))
      mail_addresses.each do |mail_address|
        @preset_headers[{{header_type}}].add(mail_address)
      end
    end

    # Adds multiple email addresses to **{{header_type.id.split("_").map(&.capitalize).join("-").id}}** header at once.
    def {{header_type.id}}(mail_addresses : Array(EMail::Address))
      mail_addresses.each do |mail_address|
        @preset_headers[{{header_type}}].add(mail_address)
      end
    end

    # Removes all email addresses from **{{header_type.id.split("_").map(&.capitalize).join("-").id}}** header.
    def clear_{{header_type.id}}
      @preset_headers[{{header_type}}].clear
    end

  end

  add_address :from
  add_address :to
  add_address :cc
  add_address :bcc
  add_address :reply_to
end
