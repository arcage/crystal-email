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
  @command_history = [] of ::String
  @on_failed : OnFailedProc? = nil
  @use_tls = false
  @login_credential : ::Tuple(String, String)? = nil
  @esmtp_commands = Hash(String, Array(String)).new { |h, k| h[k] = Array(String).new }

  # Createss smtp client object.
  def initialize(@host : ::String, @port : ::Int32 = DEFAULT_SMTP_PORT)
    @logger = logger_setting(::STDOUT, "EMail_Client", ::Logger::INFO)
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
    ready_to_send
    sent = smtp_session {
      valid_mail = mail_validate!(mail)
      send_mail(valid_mail)
    }
    sent
  rescue ex : Error
    close_socket
    fatal_error(ex)
  end

  private def ready_to_send
    @command_history.clear
    @socket = TCPSocket.new(@host, @port)
    @helo_domain ||= "[#{socket.as(TCPSocket).local_address.address}]"
    @logger.info("Start TCP session to #{@host}:#{@port}")
  end

  private def mail_validate!(mail : Message)
    timestamp = Time.now
    mail.date timestamp
    mail.message_id String.build { |io|
      io << "<" << timestamp.epoch_ms << "." << Process.pid
      io << "." << @logger.progname << "@" << @helo_domain << ">"
    }
    mail.validate!
  end

  private def send_mail(mail : Message)
    mail_from = mail.mail_from
    recipients = mail.recipients
    sent = smtp_helo && smtp_starttls && smtp_auth && smtp_mail(mail_from) && smtp_rcpt(recipients) && smtp_data(mail.data)
    if sent
      @logger.info("Successfully sent a message from <#{mail_from.addr}> to #{recipients.size} recipient(s)")
    else
      @logger.error("Failed sending message for some reason")
      if on_failed = @on_failed
        on_failed.call(mail, @command_history)
      end
    end
    sent
  end

  private def smtp_session
    status_code, _ = smtp_responce("CONN")
    sent = if status_code == "220"
             yield
           else
             false
           end
    smtp_quit
    close_socket
    sent
  end

  private def smtp_command(command : ::String, parameter : String? = nil)
    command_and_parameter = command
    command_and_parameter += " " + parameter if parameter
    @command_history << command_and_parameter
    @logger.debug("--> #{command_and_parameter}")
    socket << command_and_parameter << "\r\n"
    socket.flush
    smtp_responce(command)
  end

  private def smtp_responce(command : ::String)
    status_code = ""
    status_messages = [] of ::String
    while (line = socket.gets)
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
    {status_code, status_messages}
  end

  private def smtp_helo
    status_code, status_messages = smtp_command("EHLO", @helo_domain)
    if status_code == "250"
      status_messages.each do |status_message|
        message_parts = status_message.strip.split(' ')
        command = message_parts.shift
        @esmtp_commands[command] = message_parts
      end
      true
    elsif status_code == "502"
      status_code, _ = smtp_command("HELO", @helo_domain)
      status_code == "250"
    end
  end

  private def smtp_starttls
    if @use_tls
      status_code, _ = smtp_command("STARTTLS")
      if (status_code == "220")
        {% if flag?(:without_openssl) %}
          @logger.error("TLS is disabled because `-D without_openssl` was passed at compile time")
          false
        {% else %}
          tls_socket = OpenSSL::SSL::Socket::Client.new(@socket.as(TCPSocket), sync_close: true, hostname: @host)
          tls_socket.sync = false
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
      login_id = login_credential[0]
      login_password = login_credential[1]
      if socket.is_a?(OpenSSL::SSL::Socket::Client)
        if @esmtp_commands["AUTH"].includes?("PLAIN")
          smtp_auth_plain(login_id, login_password)
        elsif @esmtp_commands["AUTH"].includes?("LOGIN")
          smtp_auth_login(login_id, login_password)
        else
          @logger.error("cannot found supported authentication methods")
          false
        end
      else
        @logger.error("AUTH command cannot be used without TLS")
        false
      end
    else
      true
    end
  end

  private def smtp_auth_login(login_id : String, login_password : String)
    status_code, _ = smtp_command("AUTH", "LOGIN")
    if status_code == "334"
      @logger.debug("--> Sending login id")
      socket << Base64.strict_encode(login_id) << "\r\n"
      socket.flush
      status_code_id, _ = smtp_responce("AUTH")
      if status_code_id == "334"
        @logger.debug("--> Sending login password")
        socket << Base64.strict_encode(login_password) << "\r\n"
        socket.flush
        status_code_password, _ = smtp_responce("AUTH")
        if status_code_password == "235"
          @logger.info("Authentication success with #{login_id} / ********")
          true
        else
          false
        end
      else
        false
      end
    else
      false
    end
  end

  private def smtp_auth_plain(login_id : String, login_password : String)
    credential = Base64.strict_encode("\0#{login_id}\0#{login_password}")
    status_code, _ = smtp_command("AUTH", "PLAIN #{credential}")
    if status_code == "235"
      @logger.info("Authentication success with #{login_id} / ********")
      true
    else
      false
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
      socket << mail_data
      socket.flush
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
    @socket.try(&.close)
    @socket = nil
  end
end
