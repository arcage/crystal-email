# :nodoc:
abstract class EMail::Header
  # :nodoc:
  FIELD_NAME = /\A[\x{21}-\x{39}\x{3b}-\x{7e}]+\z/
  # :nodoc:
  FIELD_BODY = /\A[\x{1}-\x{9}\x{b}\x{c}\x{e}-\x{1f}\x{20}-\x{7f}]+\z/

  # :nodoc:
  NON_VCHAR = /[^\x{9}\x{20}-\x{7e}]/
  # :nodoc:
  LINE_LENGTH = 78
  # :nodoc:
  ENCODE_DEFINITION_SIZE = 13
  # :nodoc:
  ENCODE_DEFINITION_HEAD = " =?UTF-8?B?"
  # :nodoc:
  ENCODE_DEFINITION_TAIL = "?="

  # :nodoc:
  def self.base64_encode(src_string : String, offset : Int32) : Tuple(String, Int32)
    encoded_lines = [] of String
    encoded_line = ""
    src_chars = Char::Reader.new(src_string)
    until src_chars.current_char == '\u{0}'
      encoded_size = base64_encoded_size(encoded_line.bytesize + src_chars.current_char_width)
      if offset + ENCODE_DEFINITION_SIZE + encoded_size > LINE_LENGTH
        if encoded_line.empty?
          encoded_lines << ""
        else
          encoded_lines << ENCODE_DEFINITION_HEAD + Base64.strict_encode(encoded_line.to_slice) + ENCODE_DEFINITION_TAIL
        end
        encoded_line = ""
        offset = 0
      end
      encoded_line += src_chars.current_char
      src_chars.next_char
    end
    encoded_lines << ENCODE_DEFINITION_HEAD + Base64.strict_encode(encoded_line.to_slice) + ENCODE_DEFINITION_TAIL unless encoded_line.empty?
    if last_line = encoded_lines.last?
      offset = last_line.size
    end
    {encoded_lines.join("\n"), offset}
  end

  # :nodoc:
  def self.base64_encoded_size(bytesize : Int32)
    ((((bytesize.to_f * 8 / 6).ceil) / 4).ceil * 4).to_i
  end

  # Returns header name.
  getter name

  @name : String

  # Create email header with given header name.
  def initialize(field_name : String)
    raise EMail::Error::HeaderError.new("#{field_name.inspect} is invalid as a header field name.") unless field_name =~ FIELD_NAME
    @name = field_name.split("-").map(&.capitalize).join("-")
  end

  private def body
    ""
  end

  # Returns `true` when the header body has no data.
  def empty?
    body.empty?
  end

  def to_s(io : IO)
    header_body = body
    raise EMail::Error::HeaderError.new("Header #{@name} includes invalid line break(s).") if header_body =~ /\n[^\x{9}\x{20}]/
    io << @name << ":"
    offset = @name.size + 1
    if header_body =~ FIELD_BODY
      splited_body = header_body.split(/\s+/)
      while (body_part = splited_body.shift?)
        unless offset + body_part.size < LINE_LENGTH
          io << '\n'
          offset = 0
        end
        io << ' ' << body_part
        offset += body_part.size + 1
      end
    else
      encoded_part, offset = Header.base64_encode(header_body, offset)
      io << encoded_part
    end
  end

  # Email header including multiple email addresses such as **From**, **To**, and so on.
  class AddressList < Header
    # Returns internal email address list.
    getter list

    @list = [] of Address

    private def body
      @list.join(", ")
    end

    # Returns `true` when the list has no email address.
    def empty?
      @list.empty?
    end

    # Returns the number of included email addresses.
    def size
      @list.size
    end

    # Adds email address.
    def add(mail_address : String, sender_name : String? = nil)
      @list << Address.new(mail_address, sender_name)
    end

    # Adds email address.
    def add(mail_address : Address)
      @list << mail_address
    end
  end

  # Email header including only one email addresses such as **Sender**.
  class SingleAddress < Header
    @addr : Address? = nil

    private def body
      addr.to_s
    end

    # Returns `true` when the email address is not set.
    def empty?
      @addr.nil?
    end

    # Returns set email address.
    #
    # When empty, raises an excepotion.
    def addr
      @addr.not_nil!
    end

    # Set email address.
    def set(mail_address : String, sender_name : String? = nil)
      @addr = Address.new(mail_address, sender_name)
    end

    # Set email address.
    def set(mail_address : Address)
      @addr = mail_address
    end
  end

  # **Date** header.
  class Date < Header
    RFC2822_FORMAT = "%a, %d %b %Y %T %z"

    @timestamp : Time? = nil

    def initialize
      super("Date")
    end

    # Set date-time.
    def time=(time : Time)
      @timestamp = time
    end

    # Return `true` when the date-time is not set.
    def empty?
      @timestamp.nil?
    end

    private def body
      @timestamp.not_nil!.to_s(RFC2822_FORMAT)
    end
  end

  # Email headers that has no specific format such as **Subject**.
  class Unstructured < Header
    @text : String = ""

    private def body
      @text
    end

    # Set header body text.
    def set(body_text : String)
      @text = body_text
    end
  end

  # **Mime-Version** header.
  class MimeVersion < Header
    def initialize(@version : String = "1.0")
      super("Mime-Version")
    end

    private def body
      @version
    end
  end

  # **Content-Type** header
  class ContentType < Header
    @mime_type : String
    @params : Hash(String, String)

    def initialize(@mime_type : String, @params = Hash(String, String).new)
      super("Content-Type")
    end

    # Set Media type parameter
    def set_parameter(name : String, value : String)
      @params[name] = value
    end

    # Set MIME type and subtype.
    def set_mime_type(mime_type : String)
      @mime_type = mime_type
    end

    # Set "charset" parameter.
    def set_charset(charset : String)
      @params["charset"] = charset
    end

    # Set "file_name" parameter.
    def set_fname(file_name : String)
      @params["file_name"] = file_name
    end

    # Set "boundary" parameter.
    def set_boundary(boundary : String)
      @params["boundary"] = boundary
    end

    private def body
      String.build do |body_text|
        body_text << @mime_type << ';'
        if charset = @params["charset"]?
          body_text << " charset=" << charset << ';'
        end
        if fname = @params["file_name"]?
          body_text << " name=\""
          encoded_fname, _ = Header.base64_encode(fname, 6)
          body_text << encoded_fname.strip.gsub(/\n +/, ' ') << "\";"
        end
        if boundary = @params["boundary"]?
          body_text << " boundary=\"" << boundary << "\";"
        end
      end
    end
  end

  # **Content-Trandfer-Encoding** Header
  class ContentTransferEncoding < Header
    def initialize(@encoding : String)
      super("Content-Transfer-Encoding")
    end

    # Set endoding.
    def set(encoding : String)
      @encoding = encoding
    end

    private def body
      @encoding
    end
  end

  # **Content-Disposition** header.
  class ContentDisposition < Header
    @file_name : String

    def initialize(@file_name : String)
      super("Content-Disposition")
    end

    private def body
      String.build do |body_text|
        body_text << "attachment; " << encoded_fname(@file_name)
      end
    end

    private def encoded_fname(file_name : String)
      encoded_lines = [] of String
      fname_chars = Char::Reader.new(file_name)
      encoded_line = " filename*#{encoded_lines.size}*=UTF-8''"
      until fname_chars.current_char == '\u{0}'
        fname_char = URI.encode(fname_chars.current_char.to_s)
        line_size = encoded_line.size + fname_chars.current_char_width * 3
        unless line_size < LINE_LENGTH
          encoded_lines << encoded_line + ";"
          encoded_line = " filename*#{encoded_lines.size}*="
        end
        encoded_line += fname_char
        fname_chars.next_char
      end
      encoded_lines << encoded_line + ";" unless encoded_line =~ /\=\z/
      encoded_lines.join
    end
  end

  # **Content-ID** header.
  class ContentID < SingleAddress
    def initialize
      super("Content-Id")
    end
  end
end
