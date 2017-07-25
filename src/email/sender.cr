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

  def initialize(@server_host, @server_port = EMail::DEFAULT_SMTP_PORT,
                 @client_name = "EMail_Client", @log_level = Logger::INFO,
                 @helo_domain = nil, @on_failed = nil,
                 @use_tls = false, @auth = nil, @log_io = STDOUT)
  end

  def <<(message : Message)
    @queue << message
  end

  def <<(messages : Array(Message))
    @queue += messages
  end

  def start(number_of_connections : Int32, messages_per_connection : Int32 = 100)
    raise Error::SenderError.new("Number of connections must be 1 or greater") if number_of_connections < 1
    raise Error::SenderError.new("Messages per connection must be 1 or greater") if messages_per_connection < 1
    number_of_connections.times do
      spawn do
        message = @queue.shift?
        until message.nil?
          client_name = @client_name + (number_of_connections == 1 ? "" : "_#{@client_count}")
          client = Client.new(@server_host, @server_port,
            client_name: client_name, log_level: @log_level,
            helo_domain: @helo_domain, on_failed: @on_failed,
            use_tls: @use_tls, auth: @auth, log_io: @log_io)
          @clients << client
          @client_count += 1
          client.start do
            sent_messages = 0
            while message && sent_messages < messages_per_connection
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
    Fiber.yield
    until @clients.empty?
      Fiber.yield
    end
  end
end
