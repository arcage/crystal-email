# Base class for a single e-Mail content part.
abstract class EMail::Content
  @mime_type : String
  @data : String = ""
  @content_type : Header::ContentType
  @other_headers = Array(Header).new

  # :nodoc:
  def initialize(@mime_type : String)
    @content_type = Header::ContentType.new(@mime_type)
  end

  def headers
    [content_type, content_transfer_encoding] + @other_headers
  end

  private def read_data(io : IO)
    buf = Bytes.new(54)
    lines = [] of String
    while ((bytes = io.read(buf)) > 0)
      lines << Base64.strict_encode(buf[0, bytes])
    end
    lines.join("\n")
  end

  private def content_type
    @content_type
  end

  private def content_transfer_encoding
    Header::ContentTransferEncoding.new("base64")
  end

  def data(with_header : Bool = false)
    String.build do |io|
      if with_header
        headers.each do |header|
          io << header << "\n" unless header.empty?
        end
        io << "\n"
      end
      io << @data
    end
  end

  def to_s(io : IO)
    io << data(with_header: true)
  end

  def empty?
    @data.empty?
  end

  class TextPlain < Content
    def initialize
      super("text/plain")
      @content_type.set_charset("UTF-8")
    end

    def message=(message_body : String)
      @data = read_data(::IO::Memory.new(message_body))
    end
  end

  class TextHTML < Content
    def initialize
      super("text/html")
      @content_type.set_charset("UTF-8")
    end

    def message=(message_body : String)
      @data = read_data(::IO::Memory.new(message_body))
    end
  end

  class AttachmentFile < Content
    # :nodoc:
    NAME_TO_ENCODE = /[^\w\_\-\. ]/

    def initialize(file_path : String, file_id : String? = nil, file_name : String? = nil, mime_type : String? = nil)
      file_name ||= file_path.split(/\//).last
      raise Error::ContentError.new("Attached file #{file_path} is not exist.") unless File.file?(file_path)
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
      @data = read_data(io)
    end
  end

  class Multipart < Content
    @@boundaries = Set(String).new

    def self.boundary
      boundary_string = ""
      while boundary_string.empty? || @@boundaries.includes?(boundary_string)
        boundary_string = String.build do |str|
          str << "Multipart_Boundary_"
          str << Time.now.epoch_ms
          str << "_"
          str << rand(UInt32::MAX)
          str << "--"
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

    private def content_transfer_encoding
      Header::ContentTransferEncoding.new("7bit")
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
            io << header << "\n" unless header.empty?
          end
          io << "\n"
        end
        @contents.each do |content|
          io << "\n--" << @boundary << "\n"
          io << content << "\n"
        end
        io << "\n--" << @boundary
      end
    end
  end
end
