abstract class EMail::Content
  @mime_type : String
  @data : String = ""
  @content_type : Header::ContentType

  # :nodoc:
  def initialize(@mime_type : ::String)
    @content_type = Header::ContentType.new(@mime_type)
  end

  def headers
    [content_type, content_transfer_encoding]
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

    # :nodoc:
    def message=(message_body : ::String)
      @data = read_data(::MemoryIO.new(message_body))
    end
  end

  class AttachedFile < Content
    # :nodoc:
    NAME_TO_ENCODE = /[^\w\_\-\. ]/

    @file_name : String

    def initialize(file_path : String, file_name : String? = nil, mime_type : ::String? = nil)
      file_name ||= file_path.split(/\//).last
      raise Error::AttachedFileNotFound.new(file_path) unless File.file?(file_path)
      File.open(file_path) do |io|
        initialize(io, file_name, mime_type)
      end
    end

    def initialize(io : IO, @file_name : String, mime_type : ::String? = nil)
      extname = if @file_name =~ /(\.[^\.]+)\z/
                  $1
                else
                  ""
                end
      mime_type ||= (EMail::MIME_TYPE[extname]? || "application/octet-stream")
      super(mime_type)
      @content_type.set_fname(@file_name)
      @data = read_data(io)
    end

    private def content_disposition
      Header::ContentDisposition.new(@file_name)
    end

    def headers
      super() << content_disposition
    end
  end
end
