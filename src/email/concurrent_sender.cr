# Utility object for concurrent email sending.
#
# ```crystal
# rcpt_list = ["a@example.com", "b@example.com", "c@example.com", "d@example.com"]
#
# # Set SMTP client configuration
# config = EMail::Client::Config.new("your.mx.example.com", 25)
#
# # Create concurrent sender object
# sender = EMail::ConcurrentSender.new(config)
#
# # Sending emails with concurrently 3 connections.
# sender.number_of_connections = 3
#
# # Sending max 10 emails by 1 connection.
# sender.messages_per_connection = 10
#
# # Start email sending.
# sender.start do
#   # In this block, default receiver is sender
#   rcpt_list.each do |rcpt_to|
#     # Create email message
#     mail = EMail::Message.new
#     mail.from "your_addr@example.com"
#     mail.to rcpt_to
#     mail.subject "Concurrent email sending"
#     mail.message "message to #{rcpt_to}"
#     # Enqueue the email to sender
#     enqueue mail
#   end
# end
# ```
class EMail::ConcurrentSender
  @config : EMail::Client::Config
  @queue : Array(Message) = Array(Message).new
  @connections : Array(Fiber) = Array(Fiber).new
  @connection_count : Int32 = 0
  @started : Bool = false
  @finished : Bool = false
  @number_of_connections : Int32 = 1
  @messages_per_connection : Int32 = 10
  @connection_interval : Int32 = 200

  # Create sender object with given client settings as EMail::Client::Config object.
  def initialize(@config)
  end

  # Send one email with given client settings as several arguments.
  #
  # Avairable arguments are same as `EMail::Client::Conifg.create` method.
  def initialize(*args, **named_args)
    initialize(EMail::Client::Config.create(*args, **named_args))
  end

  # Set the maximum number of SMTP connections established at the same time.
  def number_of_connections=(new_value : Int32)
    raise EMail::Error::SenderError.new("Parameters cannot be set after start sending") if @started
    raise EMail::Error::SenderError.new("Number of connections must be 1 or greater(given: #{new_value})") if new_value < 1
    @number_of_connections = new_value
  end

  # Set the maximum number of email messages sent by one SMTP connection.
  #
  # When the number of sent emails by some SMTP connection reaches this parameter, the current connection will be closed and new one will be opened.
  def messages_per_connection=(new_value : Int32)
    raise EMail::Error::SenderError.new("Parameters cannot be set after start sending") if @started
    raise EMail::Error::SenderError.new("Messages per connection must be 1 or greater(given: #{new_value})") if new_value < 1
    @messages_per_connection = new_value
  end

  # Set the interval milliseconds between some connection is closed and new one is opened.
  def connection_interval=(new_interval : Int32)
    raise EMail::Error::SenderError.new("Parameters cannot be set after start sending") if @started
    raise EMail::Error::SenderError.new("Connection interval must be 0 or greater(given: #{new_interval})") if new_interval < 0
    @connection_interval = new_interval
  end

  # Enqueue a email message.
  def enqueue(message : Message)
    @queue << message.validate!
    Fiber.yield
  end

  # Encueue email messages at the same time.
  def enqueue(messages : Array(Message))
    messages.each do |message|
      enqueue(message)
    end
  end

  # Starts sending emails.
  #
  # In the block of this method, the default receiver is `self`
  def start
    raise EMail::Error::SenderError.new("Email sending is already started") if @started
    @started = true
    spawn_sender
    with self yield
    @finished = true
    until @queue.empty? && @connections.empty?
      Fiber.yield
    end
    @started = false
    @finished = false
  end

  # Starts sending emails with given parameters.
  def start(number_of_connections : Int32? = nil, messages_per_connection : Int32? = nil, connection_interval : Int32? = nil)
    raise EMail::Error::SenderError.new("Email sending is already started") if @started
    self.number_of_connections = number_of_connections if number_of_connections
    self.messages_per_connection = messages_per_connection if messages_per_connection
    self.connection_interval = connection_interval if connection_interval
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
        @connection_count += 1
        client = Client.new(@config, @connection_count)
        client.number = @connection_count
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

module EMail
  alias Sender = EMail::ConcurrentSender
end
