# Utility object for concurrent email sending.
class EMail::Sender
  @queue : Array(Message) = Array(Message).new
  @connections : Array(Fiber) = Array(Fiber).new
  @connection_count : Int32 = 0
  @server_host : String
  @server_port : Int32
  @client_name : String
  @helo_domain : String?
  @on_failed : EMail::Client::OnFailedProc?
  @on_fatal_error : EMail::Client::OnFatalErrorProc?
  @use_tls : Bool
  @openssl_verify_mode : String?
  @auth : Tuple(String, String)?
  @logger : Logger
  @finished : Bool = false
  @number_of_connections : Int32 = 1
  @messages_per_connection : Int32 = 10
  @connection_interval : Int32 = 200

  def initialize(@server_host, @server_port = EMail::DEFAULT_SMTP_PORT, *,
                 @client_name = EMail::Client::DEFAULT_NAME, @helo_domain = nil,
                 @use_tls = false, @auth = nil, @openssl_verify_mode = nil,
                 @on_failed = nil, @on_fatal_error = nil,
                 @logger : Logger)
  end

  def initialize(server_host : String, server_port : Int32 = EMail::DEFAULT_SMTP_PORT, *,
                 client_name : String = EMail::Client::DEFAULT_NAME, helo_domain : String? = nil,
                 on_failed : EMail::Client::OnFailedProc? = nil, on_fatal_error : EMail::Client::OnFatalErrorProc? = nil,
                 use_tls : Bool = false, auth : Tuple(String, String)? = nil, openssl_verify_mode : String? = nil,
                 log_io : IO? = nil, log_progname : String? = nil,
                 log_formatter : Logger::Formatter? = nil, log_level : Logger::Severity? = nil)
    logger = EMail::Client.create_default_logger(log_io, log_progname, log_formatter, log_level)
    initialize(server_host, server_port,
      client_name: client_name, helo_domain: helo_domain,
      on_failed: on_failed, on_fatal_error: on_fatal_error, use_tls: use_tls,
      auth: auth, openssl_verify_mode: openssl_verify_mode logger: logger)
  end

  def enqueue(message : Message)
    @queue << message.validate!
    Fiber.yield
  end

  def enqueue(messages : Array(Message))
    messages.each do |message|
      enqueue(message)
    end
  end

  def start(number_of_connections : Int32? = nil, messages_per_connection : Int32? = nil, connection_interval : Int32? = nil)
    if number_of_connections
      @number_of_connections = number_of_connections
    end
    if messages_per_connection
      @messages_per_connection = messages_per_connection
    end
    if connection_interval
      @connection_interval = connection_interval
    end
    raise EMail::Error::SenderError.new("Number of connections must be 1 or greater") if @number_of_connections < 1
    raise EMail::Error::SenderError.new("Messages per connection must be 1 or greater") if @messages_per_connection < 1
    raise EMail::Error::SenderError.new("Connection interval must be 0 or greater") if @connection_interval < 0
    spawn_sender
    with self yield
    @finished = true
    until @queue.empty? && @connections.empty?
      Fiber.yield
    end
  end

  private def spawn_sender
    spawn do
      until @finished && @queue.empty?
        spawn_client if !@queue.empty? && @connections.size < @number_of_connections
        Fiber.yield
      end
    end
  end

  private def spawn_client
    spawn do
      @connections << Fiber.current
      message = @queue.shift?
      while message
        client_name = @client_name + (@connection_count == 0 ? "" : "_#{@connection_count}")
        client = Client.new(@server_host, @server_port,
          client_name: client_name, helo_domain: @helo_domain,
          openssl_verify_mode: @openssl_verify_mode, auth: @auth, logger: @logger,
          on_failed: @on_failed, on_fatal_error: @on_fatal_error, use_tls: @use_tls)
        @connection_count += 1
        client.start do
          sent_messages = 0
          while message && sent_messages < @messages_per_connection
            send(message)
            sent_messages += 1
            Fiber.yield
            message = @queue.shift?
          end
        end
        sleep(@connection_interval.milliseconds) if @connection_interval > 0
      end
      @connections.delete(Fiber.current)
    end
  end
end
