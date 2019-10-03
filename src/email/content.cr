# :nodoc:
abstract class EMail::Content
  @mime_type : String
  @data : String = ""
  @content_type : Header::ContentType
  @other_headers = Array(Header).new
  @content_transfer_encoding = Header::ContentTransferEncoding.new("7bit")

  # :nodoc:
  def initialize(@mime_type : String)
    @content_type = Header::ContentType.new(@mime_type)
  end

  # Returns the list of email header of this content.
  def headers
    [content_type, content_transfer_encoding] + @other_headers
  end

  private def encode_data(str : String)
    encode_data(IO::Memory.new(str))
  end

  private def encode_data(io : IO)
    @content_transfer_encoding.set("base64")
    line_size = 54
    buf = Bytes.new(line_size)
    lines = [] of String
    while ((bytes = io.read(buf)) > 0)
      unless bytes == line_size
        rest_buf = Bytes.new(line_size - bytes)
        if (rest_bytes = io.read(rest_buf)) > 0
          (0..rest_bytes - 1).each do |i|
            buf[bytes + i] = rest_buf[i]
          end
          bytes += rest_bytes
        end
      end
      lines << Base64.strict_encode(buf[0, bytes])
    end
    lines.join('\n')
  end

  private def content_type
    @content_type
  end

  private def content_transfer_encoding
    @content_transfer_encoding
  end

  # Write content data to `io`.
  def data(io : IO, with_header : Bool)
    if with_header
      headers.each do |header|
        io << header << '\n' unless header.empty?
      end
      io << '\n'
    end
    io << @data
  end

  # Returns content data as String.
  def data(with_header : Bool = false)
    String.build do |io|
      data(io, with_header)
    end
  end

  def to_s(io : IO)
    io << data(with_header: true)
  end

  # Returns `true` when this content has no data.
  def empty?
    @data.empty?
  end

  # :nodoc:
  class TextContent < Content
    # Create content with given MIME subtype of text.
    #
    # When `text_typr` is `plain`, the Mediatype of this content is `text/plain`.
    def initialize(text_type : String)
      super("text/#{text_type}")
      @content_type.set_charset("UTF-8")
    end

    # Set content text.
    def data=(message_body : String)
      encoded = !message_body.ascii_only? || message_body.split(/\r?\n/).map(&.size).max > 998
      @data = (encoded ? encode_data(message_body) : message_body)
    end

    private def line_validate(message_body : String)
      String.build do |str|
        message_body.split(/\r?\n/) do |line|
          while line.size > 990
            str << line[0, 990]
            str << "!\n"
            line = line[990, (line.size - 990)]
          end
          str << line
          str << '\n'
        end
      end
    end
  end

  # :nodoc:
  class AttachmentFile < Content
    # :nodoc:
    NAME_TO_ENCODE = /[^\w\_\-\. ]/

    def initialize(file_path : String, file_id : String? = nil, file_name : String? = nil, mime_type : String? = nil)
      file_name ||= file_path.split(/\//).last
      raise EMail::Error::ContentError.new("Attached file #{file_path} is not exist.") unless File.file?(file_path)
      File.open(file_path) do |io|
        initialize(io, file_id: file_id, file_name: file_name, mime_type: mime_type)
      end
    end

    def initialize(io : IO, @file_id : String?, @file_name : String, mime_type : String? = nil)
      extname = if @file_name =~ /(\.[^\.]+)\z/
                  $1
                else
                  ""
                end
      mime_type ||= (EMail::MIME_TYPE[extname]? || "application/octet-stream")
      super(mime_type)
      @content_type.set_fname(@file_name)
      @other_headers << Header::ContentDisposition.new(@file_name)
      if file_id = @file_id
        content_id = Header::ContentID.new
        content_id.set (file_id)
        @other_headers << content_id
      end
      @data = encode_data(io)
    end
  end

  class Multipart < Content
    @@boundaries = Set(String).new

    def self.boundary
      boundary_string = ""
      while boundary_string.empty? || @@boundaries.includes?(boundary_string)
        boundary_string = String.build do |str|
          str << "Multipart_Boundary_"
          str << Time.local.to_unix_ms
          str << '_'
          str << rand(UInt32::MAX)
        end
      end
      @@boundaries << boundary_string
      boundary_string
    end

    @contents = Array(Content).new
    @boundary : String

    def initialize(multipart_type : String)
      super("multipart/#{multipart_type}")
      @boundary = Multipart.boundary
      @content_type.set_boundary(@boundary)
    end

    def add(content : Content)
      @contents << content
      self
    end

    def <<(content : Content)
      add(content)
    end

    def data(with_header : Bool = false)
      String.build do |io|
        if with_header
          headers.each do |header|
            io << header << '\n' unless header.empty?
          end
          io << '\n'
        end
        @contents.each do |content|
          io << "\n--" << @boundary << '\n'
          io << content << '\n'
        end
        io << "\n--" << @boundary << "--"
      end
    end
  end
end
