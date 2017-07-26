class EMail::Sender
  @queue : Array(Message) = Array(Message).new
  @clients : Array(Client) = Array(Client).new
  @client_count : Int32 = 0
  @server_host : String
  @server_port : Int32
  @client_name : String
  @log_level : Logger::Severity
  @helo_domain : String?
  @on_failed : Client::OnFailedProc?
  @use_tls : Bool
  @auth : Tuple(String, String)?
  @log_io : IO
  @finished : Bool = false
  @number_of_connections : Int32 = 1
  @messages_per_connection : Int32 = 100

  def initialize(@server_host, @server_port = EMail::DEFAULT_SMTP_PORT,
                 @client_name = "EMail_Client", @log_level = Logger::INFO,
                 @helo_domain = nil, @on_failed = nil,
                 @use_tls = false, @auth = nil, @log_io = STDOUT)
  end

  def enqueue(message : Message)
    @queue << message
    Fiber.yield
  end

  def enqueue(messages : Array(Message))
    messages.each do |message|
      enqueue(message)
    end
  end

  def start(number_of_connections : Int32? = nil, messages_per_connection : Int32? = nil)
    if number_of_connections
      @number_of_connections = number_of_connections
    end
    if messages_per_connection
      @messages_per_connection = messages_per_connection
    end
    raise Error::SenderError.new("Number of connections must be 1 or greater") if @number_of_connections < 1
    raise Error::SenderError.new("Messages per connection must be 1 or greater") if @messages_per_connection < 1
    spawn_sender
    with self yield
    @finished = true
    until @queue.empty? && @clients.empty?
      Fiber.yield
    end
  end

  private def spawn_sender
    spawn do
      until @finished && @queue.empty?
        spawn_client if !@queue.empty? && @clients.size < @number_of_connections
        Fiber.yield
      end
    end
  end

  private def spawn_client
    spawn do
      message = @queue.shift?
      until message.nil?
        client_name = @client_name + (@number_of_connections == 1 ? "" : "_#{@client_count}")
        client = Client.new(@server_host, @server_port,
          client_name: client_name, log_level: @log_level,
          helo_domain: @helo_domain, on_failed: @on_failed,
          use_tls: @use_tls, auth: @auth, log_io: @log_io)
        @clients << client
        @client_count += 1
        client.start do
          sent_messages = 0
          while message && sent_messages < @messages_per_connection
            send(message)
            sent_messages += 1
            Fiber.yield
            message = @queue.shift?
          end
        end
        @clients.delete(client)
      end
    end
  end
end
