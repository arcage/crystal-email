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
  {% if flag?(:without_openssl) %}
    @socket : ::TCPSocket? = nil
  {% else %}
    @socket : ::TCPSocket | OpenSSL::SSL::Socket::Client | Nil = nil
  {% end %}
  @helo_domain : ::String? = nil
  @command_history : ::Array(::String) = [] of ::String
  @on_failed : OnFailedProc? = nil
  @use_tls : Bool = false
  @login_credential : ::Tuple(String, String)? = nil

  # Createss smtp client object.
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

  def auth=(login_credential : Tuple(::String, ::String))
    @login_credential = login_credential
  end

  def use_tls=(use_tls : Bool)
    {% if flag?(:without_openssl) %}
      if use_tls
        raise Error::ClientError.new("TLS is disabled because `-D without_openssl` was passed at compile time")
      end
    {% end %}
    @use_tls = use_tls
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
    @helo_domain ||= "[#{socket.as(TCPSocket).local_address.address}]"
    @logger.info("Start TCP session to #{@host}:#{@port}")
    timestamp = Time.now
    mail.date timestamp
    mail.message_id String.build { |io|
      io << timestamp.epoch_ms << "." << Process.pid
      io << "." << @logger.progname << "@[" << @helo_domain << "]"
    }
    mail_from = mail.mail_from
    recipients = mail.recipients
    sent = smtp_start && smtp_helo && smtp_starttls && smtp_auth && smtp_mail(mail_from) && smtp_rcpt(recipients) && smtp_data(mail.data)
    smtp_quit
    close_socket
    if sent
      @logger.info("Successfully sent a message from <#{mail_from.addr}> to #{recipients.size} recipient(s)")
    else
      @logger.error("Failed sending message for some reason")
      if on_failed = @on_failed
        on_failed.call(mail, @command_history)
      end
    end
    sent
  rescue ex : Error
    close_socket
    fatal_error(ex)
  end

  private def smtp_command(command : ::String, parameter : String? = nil)
    command_and_parameter = command
    command_and_parameter += " " + parameter if parameter
    @command_history << command_and_parameter
    @logger.debug("--> #{command_and_parameter}")
    socket.write (command_and_parameter + "\r\n").to_slice
    smtp_responce(command)
  end

  private def smtp_responce(command : ::String)
    status_code = ""
    status_messages = [] of ::String
    while (line = socket.gets)
      line = line.chomp
      @command_history << line
      if line =~ /\A(\d{3})((( |-)(.*))?)\z/
        continue = false
        unless $2.empty?
          continue = ($4 == "-")
          status_messages << $5.to_s unless $5.empty?
        end
        unless continue
          status_code = $1
          break
        end
      else
        raise Error::ClientError.new("Invalid responce \"#{line}\" received.")
      end
    end
    status_message = status_messages.join(" / ")
    logging_message = "<-- #{command} #{status_code} #{status_message}"
    case status_code[0]
    when '4', '5'
      @logger.error(logging_message)
    else
      @logger.debug(logging_message)
    end
    {status_code, status_message}
  end

  private def smtp_start
    status_code, _ = smtp_responce("CONN")
    status_code == "220"
  end

  private def smtp_helo
    status_code, _ = smtp_command("EHLO", @helo_domain)
    if status_code == "250"
      true
    elsif status_code == "502"
      status_code, _ = smtp_command("HELO", @helo_domain)
      status_code == "250"
    end
  end

  private def smtp_starttls
    if @use_tls
      _status_code, _status_message = smtp_command("STARTTLS")
      if (_status_code == "220")
        {% if flag?(:without_openssl) %}
          @logger.error("TLS is disabled because `-D without_openssl` was passed at compile time")
          false
        {% else %}
          tls_socket = OpenSSL::SSL::Socket::Client.new(@socket.as(TCPSocket), sync_close: true, hostname: @host)
          @logger.info("Start TLS session")
          @socket = tls_socket
          smtp_helo
        {% end %}
      else
        false
      end
    else
      true
    end
  end

  private def smtp_auth
    login_credential = @login_credential
    if login_credential
      if socket.is_a?(OpenSSL::SSL::Socket::Client)
        login_id = login_credential[0]
        login_password = login_credential[1]
        credential = Base64.strict_encode("\0#{login_id}\0#{login_password}")
        status_code, status_message = smtp_command("AUTH", "PLAIN #{credential}")
        if status_code == "235"
          @logger.info("Authentication success with #{login_id} / ********")
          true
        else
          false
        end
      else
        @logger.error("AUTH PLAIN command can not be used without TLS")
        false
      end
    else
      true
    end
  end

  private def smtp_mail(mail_from : Address)
    status_code, _ = smtp_command("MAIL", "FROM:<#{mail_from.addr}>")
    status_code == "250"
  end

  private def smtp_rcpt(recipients : ::Array(Address))
    succeed = true
    recipients.each do |recipient|
      status_code, status_message = smtp_command("RCPT", "TO:<#{recipient.addr}>")
      succeed = false unless status_code[0] == '2'
    end
    succeed
  end

  private def smtp_data(mail_data : ::String)
    status_code, _ = smtp_command("DATA")
    if status_code == "354"
      @logger.debug("--> Sending mail data")
      socket.write mail_data.to_slice
      status_code, _ = smtp_responce("DATA")
      status_code[0] == '2'
    else
      false
    end
  end

  private def smtp_quit
    smtp_command("QUIT")
  end

  private def fatal_error(error : ::Exception)
    logging_message = error.message.try(&.gsub(/\s+/, " ")).to_s + "(#{error.class})"
    @logger.fatal(logging_message)
    exit(1)
  end

  def close_socket
    if _socket = @socket
      _socket.close unless _socket.closed?
    end
    @socket = nil
  end
end
