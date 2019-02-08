# Utility object for concurrent email sending.
class EMail::Sender
  @config : EMail::Client::Config
  @queue : Array(Message) = Array(Message).new
  @connections : Array(Fiber) = Array(Fiber).new
  @connection_count : UInt32 = 0
  @started : Bool = false
  @finished : Bool = false
  @number_of_connections : Int32 = 1
  @messages_per_connection : Int32 = 10
  @connection_interval : Int32 = 200

  def initialize(@config)
  end

  def initialize(*args, **named_args)
    initialize(EMail::Client::Config.create(*args, **named_args))
  end

  def number_of_connections=(new_value : Int32)
    raise EMail::Error::SenderError.new("Parameters cannot be set after start sending") if @started
    raise EMail::Error::SenderError.new("Number of connections must be 1 or greater(given: #{new_value})") if new_value < 1
    @number_of_connections = new_value
  end

  def messages_per_connection=(new_value : Int32)
    raise EMail::Error::SenderError.new("Parameters cannot be set after start sending") if @started
    raise EMail::Error::SenderError.new("Messages per connection must be 1 or greater(given: #{new_value})") if new_value < 1
    @messages_per_connection = new_value
  end

  def connection_interval=(new_interval : Int32)
    raise EMail::Error::SenderError.new("Parameters cannot be set after start sending") if @started
    raise EMail::Error::SenderError.new("Connection interval must be 0 or greater(given: #{new_interval})") if new_interval < 0
    @connection_interval = new_interval
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

  def start
    @started = true
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
        client = Client.new(@config)
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
