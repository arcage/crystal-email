class EMail::Client
  alias OnFailedProc = Message, ::Array(::String) ->

  # :nodoc:
  LOG_FORMATTER = Logger::Formatter.new do |severity, datetime, progname, message, io|
    io << datetime.to_s("%Y/%m/%d %T") << " [" << progname << "/" << Process.pid << "] "
    io << severity << " " << message
  end

  NO_LOGGING = Logger::Severity::UNKNOWN

  # :nodoc:
  DOMAIN_FORMAT = /\A[a-zA-Z0-9\!\#\$\%\&\'\*\+\-\/\=\?\^\_\`^{\|\}\~]+(\.[a-zA-Z0-9\!\#\$\%\&\'\*\+\-\/\=\?\^\_\`^{\|\}\~]+)+\z/

  getter command_history

  @host : ::String
  @port : ::Int32
  @logger : ::Logger
  @local_host : ::String = ""
  @socket : ::TCPSocket? = nil
  @helo_domain : ::String? = nil
  @command_history : ::Array(::String) = [] of ::String
  @on_failed : OnFailedProc? = nil

  def initialize(@host : ::String, @port : ::Int32 = DEFAULT_SMTP_PORT)
    @logger = logger_setting(::STDOUT, "EMail_Client", ::Logger::INFO)
  rescue ex : Error
    fatal_error(ex)
  end

  private def logger_setting(io : IO, progname : ::String, level : ::Logger::Severity)
    logger = ::Logger.new(io)
    logger.progname = progname
    logger.formatter = LOG_FORMATTER
    logger.level = level
    logger
  end

  def log_level=(level : ::Logger::Severity)
    @logger.level = level
  end

  def client_name=(client_name : ::String)
    raise Error::ClientError.new("Invalid client name \"#{client_name}\"") if client_name.empty? || client_name =~ /[^\w]/
    @logger.progname = client_name
  end

  def helo_domain=(domain : ::String)
    raise Error::ClientError.new("Invalid HELO domain \"#{domain}\"") unless domain =~ DOMAIN_FORMAT
    @helo_domain = domain
  end

  def on_failed=(on_failed : OnFailedProc)
    @on_failed = on_failed
  end

  private def socket
    if _socket = @socket
      _socket
    else
      raise Error::ClientError.new("Client socket not opened.")
    end
  end

  def send(mail : Message)
    mail.validate!
    @command_history.clear
    @socket = TCPSocket.new(@host, @port)
    @helo_domain ||= "[#{socket.local_address.address}]"
    @logger.info("OK: successfully connected to #{@host}")
    timestamp = Time.now
    mail.date timestamp
    mail.message_id String.build { |io|
      io << timestamp.epoch_ms << "." << Process.pid
      io << "." << @logger.progname << "@[" << @helo_domain << "]"
    }
    mail_from = mail.mail_from
    recipients = mail.recipients
    sent = call_helo && call_mail(mail_from) && call_rcpt(recipients) && call_data(mail.data)
    call_quit
    if sent
      @logger.info("OK: successfully sent message from <#{mail_from.addr}> to #{recipients.size} recipient(s)")
    else
      @logger.info("NG: failed sending message for some reason")
      if on_failed = @on_failed
        on_failed.call(mail, @command_history)
      end
    end
    sent
  rescue ex : Error
    fatal_error(ex)
  end

  private def server_call(smtp_command : ::String)
    smtp_command = smtp_command.chomp
    @command_history << smtp_command
    @logger.debug("--> #{smtp_command}")
    socket.write (smtp_command + "\r\n").to_slice
    server_responce
  end

  private def server_responce
    status_code = ""
    status_messages = [] of ::String
    while (line = socket.gets)
      line = line.chomp
      @command_history << line
      if line =~ /\A(\d{3})( |-)(.*)\z/
        sp = $2
        status_messages << $3
        if sp == " "
          status_code = $1
          break
        end
      else
        raise Error::ClientError.new("Invalid responce \"#{line}\" received.")
      end
    end
    status_message = status_messages.join(" ")
    logging_message = "<-- #{status_code} #{status_message}"
    case status_code[0]
    when '4', '5'
      @logger.error(logging_message)
    else
      @logger.debug(logging_message)
    end
    {status_code, status_message}
  end

  private def call_helo
    status_code, _ = server_responce
    if status_code == "220"
      status_code, _ = server_call("EHLO #{@helo_domain}")
      if status_code == "250"
        true
      elsif status_code == "502"
        status_code, _ = server_call("HELO #{@helo_domain}")
        status_code == "250"
      end
    else
      false
    end
  end

  private def call_mail(mail_from : Address)
    status_code, _ = server_call("MAIL FROM:<#{mail_from.addr}>")
    status_code == "250"
  end

  private def call_rcpt(recipients : ::Array(Address))
    succeed = true
    recipients.each do |recipient|
      status_code, status_message = server_call("RCPT TO:<#{recipient.addr}>")
      succeed = false unless status_code[0] == '2'
    end
    succeed
  end

  private def call_data(mail_data : ::String)
    status_code, _ = server_call("DATA")
    if status_code == "354"
      @logger.debug("--> Sending mail data")
      socket.write mail_data.to_slice
      status_code, _ = server_responce
      status_code[0] == '2'
    else
      false
    end
  end

  private def call_quit
    server_call("QUIT")
    socket.close
    @socket = nil
  end

  private def fatal_error(error : ::Exception)
    logging_message = error.message.try(&.gsub(/\s+/, " ")).to_s + "(#{error.class})"
    @logger.fatal(logging_message)
    exit(1)
  end
end
