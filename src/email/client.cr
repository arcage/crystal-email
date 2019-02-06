class EMail::Client
  alias OnFailedProc = Message, Array(String) ->
  alias OnFatalErrorProc = Exception ->

  LOG_FORMATTER = Logger::Formatter.new do |severity, datetime, progname, message, io|
    io << datetime.to_s("%Y/%m/%d %T") << " [" << progname << "/" << Process.pid << "] "
    io << severity << " " << message
  end
  LOG_PROGNAME = "crystal-email"
  NO_LOGGING   = Logger::Severity::UNKNOWN
  DEFAULT_NAME = "EMail_Client"

  # :nodoc:
  DOMAIN_FORMAT = /\A[a-zA-Z0-9\!\#\$\%\&\'\*\+\-\/\=\?\^\_\`^{\|\}\~]+(\.[a-zA-Z0-9\!\#\$\%\&\'\*\+\-\/\=\?\^\_\`^{\|\}\~]+)+\z/

  def self.create_default_logger(log_io : IO? = nil,
                                 log_progname : String? = nil,
                                 log_formatter : Logger::Formatter? = nil,
                                 log_level : Logger::Severity? = nil)
    log_io ||= STDOUT
    logger = Logger.new(log_io)
    logger.progname = log_progname || EMail::Client::LOG_PROGNAME
    logger.formatter = log_formatter || EMail::Client::LOG_FORMATTER
    logger.level = log_level || Logger::INFO
    logger
  end

  getter command_history

  @host : String
  @port : Int32
  @name : String
  @logger : Logger
  @started : Bool = false
  @first_send : Bool = true
  {% if flag?(:without_openssl) %}
    @socket : TCPSocket? = nil
  {% else %}
    @socket : TCPSocket | OpenSSL::SSL::Socket::Client | Nil = nil
  {% end %}
  @helo_domain : String?
  @command_history = [] of String
  @on_failed : EMail::Client::OnFailedProc?
  @on_fatal_error : EMail::Client::OnFatalErrorProc?
  @use_tls : Bool
  @openssl_verify_mode : OpenSSL::SSL::VerifyMode
  @auth : Tuple(String, String)?
  @esmtp_commands = Hash(String, Array(String)).new { |h, k| h[k] = Array(String).new }

  # Creates smtp client object.
  def initialize(@host, @port = EMail::DEFAULT_SMTP_PORT, *,
                 client_name @name = EMail::Client::DEFAULT_NAME, @helo_domain = nil,
                 @on_failed = nil, @on_fatal_error = nil, @openssl_verify_mode = OpenSSL::SSL::VerifyMode::PEER,
                 @use_tls = false, @auth = nil, logger : Logger? = nil)
    raise EMail::Error::ClientError.new("Invalid client name \"#{@name}\"") if @name.empty? || @name =~ /[^\w]/
    if helo_domain = @helo_domain
      raise EMail::Error::ClientError.new("Invalid HELO domain \"#{helo_domain}\"") unless helo_domain =~ DOMAIN_FORMAT
    end
    @logger = logger || EMail::Client.create_default_logger
    {% if flag?(:without_openssl) %}
      if @use_tls
        raise EMail::Error::ClientError.new("TLS is disabled because `-D without_openssl` was passed at compile time")
      end
    {% end %}
  end

  def initialize(server_host : String, server_port : Int32 = EMail::DEFAULT_SMTP_PORT, *,
                 client_name : String = EMail::Client::DEFAULT_NAME, helo_domain : String? = nil,
                 on_failed : EMail::Client::OnFailedProc? = nil, on_fatal_error : EMail::Client::OnFatalErrorProc? = nil,
                 use_tls : Bool = false, auth : Tuple(String, String)? = nil, openssl_verify_mode : OpenSSL::SSL::VerifyMode = OpenSSL::SSL::VerifyMode::PEER,
                 log_io : IO? = nil, log_progname : String? = nil,
                 log_formatter : Logger::Formatter? = nil, log_level : Logger::Severity? = nil)
    logger = EMail::Client.create_default_logger(log_io, log_progname, log_formatter, log_level)
    initialize(server_host, server_port,
      client_name: client_name, helo_domain: helo_domain,
      on_failed: on_failed, on_fatal_error: on_fatal_error,
      openssl_verify_mode: openssl_verify_mode,
      use_tls: use_tls, auth: auth, logger: logger)
  end

  private def socket
    if _socket = @socket
      _socket
    else
      raise EMail::Error::ClientError.new("Client socket not opened.")
    end
  end

  def start
    ready_to_send
    status_code, _ = smtp_responce("CONN")
    if status_code == "220" && smtp_helo && smtp_starttls && smtp_auth
      @started = true
      with self yield
      @started = false
    else
      log_error("Failed in connecting for some reason")
    end
    smtp_quit
  rescue error
    fatal_error(error)
  ensure
    begin
      close_socket
    rescue error
      fatal_error(error)
    end
  end

  private def ready_to_send
    @socket = TCPSocket.new(@host, @port)
    @helo_domain ||= "[#{socket.as(TCPSocket).local_address.address}]"
    log_info("Start TCP session to #{@host}:#{@port}")
  end

  private def mail_validate!(mail : Message) : Message
    timestamp = Time.now
    mail.date timestamp
    mail.message_id String.build { |io|
      io << '<' << timestamp.to_unix_ms << '.' << Process.pid
      io << '.' << @name << '@' << @helo_domain << '>'
    }
    mail.validate!
  end

  def send(mail : Message)
    raise EMail::Error::ClientError.new("Email client has not been started") unless @started
    @command_history.clear
    mail = mail_validate!(mail)
    mail_from = mail.mail_from
    recipients = mail.recipients
    if smtp_rset && smtp_mail(mail_from) && smtp_rcpt(recipients) && smtp_data(mail.data)
      log_info("Successfully sent a message from <#{mail_from.addr}> to #{recipients.size} recipient(s)")
    else
      log_error("Failed sending message for some reason")
      if on_failed = @on_failed
        on_failed.call(mail, @command_history)
      end
    end
  end

  private def smtp_command(command : String, parameter : String? = nil)
    command_and_parameter = command
    command_and_parameter += " " + parameter if parameter
    @command_history << command_and_parameter
    log_debug("--> #{command_and_parameter}")
    socket << command_and_parameter << "\r\n"
    socket.flush
    smtp_responce(command)
  end

  private def smtp_responce(command : String)
    status_code = ""
    status_messages = [] of String
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
        raise EMail::Error::ClientError.new("Invalid responce \"#{line}\" received.")
      end
    end
    status_message = status_messages.join(" / ")
    logging_message = "<-- #{command} #{status_code} #{status_message}"
    case status_code[0]
    when '4', '5'
      log_error(logging_message)
    else
      log_debug(logging_message)
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
          log_error("TLS is disabled because `-D without_openssl` was passed at compile time")
          false
        {% else %}
          tls_context = OpenSSL::SSL::Context::Client.new
          tls_context.verify_mode = @openssl_verify_mode
          tls_socket = OpenSSL::SSL::Socket::Client.new(@socket.as(TCPSocket), tls_context, sync_close: true, hostname: @host)
          tls_socket.sync = false
          log_info("Start TLS session")
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
    if login_credential = @auth
      login_id, login_password = login_credential
      if socket.is_a?(OpenSSL::SSL::Socket::Client)
        if @esmtp_commands["AUTH"].includes?("PLAIN")
          smtp_auth_plain(login_id, login_password)
        elsif @esmtp_commands["AUTH"].includes?("LOGIN")
          smtp_auth_login(login_id, login_password)
        else
          log_error("cannot found supported authentication methods")
          false
        end
      else
        log_error("AUTH command cannot be used without TLS")
        false
      end
    else
      true
    end
  end

  private def smtp_auth_login(login_id : String, login_password : String)
    status_code, _ = smtp_command("AUTH", "LOGIN")
    if status_code == "334"
      log_debug("--> Sending login id")
      socket << Base64.strict_encode(login_id) << "\r\n"
      socket.flush
      status_code_id, _ = smtp_responce("AUTH")
      if status_code_id == "334"
        log_debug("--> Sending login password")
        socket << Base64.strict_encode(login_password) << "\r\n"
        socket.flush
        status_code_password, _ = smtp_responce("AUTH")
        if status_code_password == "235"
          log_info("Authentication success with #{login_id} / ********")
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
      log_info("Authentication success with #{login_id} / ********")
      true
    else
      false
    end
  end

  private def smtp_rset
    if @first_send
      @first_send = false
      true
    else
      status_code, _ = smtp_command("RSET")
      status_code == "250"
    end
  end

  private def smtp_mail(mail_from : Address)
    status_code, _ = smtp_command("MAIL", "FROM:<#{mail_from.addr}>")
    status_code == "250"
  end

  private def smtp_rcpt(recipients : Array(Address))
    succeed = true
    recipients.each do |recipient|
      status_code, status_message = smtp_command("RCPT", "TO:<#{recipient.addr}>")
      succeed = false unless status_code[0] == '2'
    end
    succeed
  end

  private def smtp_data(mail_data : String)
    status_code, _ = smtp_command("DATA")
    if status_code == "354"
      log_debug("--> Sending mail data")
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

  def close_socket
    if _socket = @socket
      _socket.close
      log_info("Close session to #{@host}:#{@port}")
    end
    @socket = nil
  end

  def fatal_error(error : Exception)
    log_fatal(error.message.try(&.gsub(/\s+/, ' ')).to_s + "(#{error.class})")
    if on_fatal_error = @on_fatal_error
      on_fatal_error.call(error)
    end
  end

  private def log_format(message : String)
    String.build do |str|
      str << '[' << @name << "] " << message
    end
  end

  private def log_debug(message : String)
    @logger.debug(log_format(message))
  end

  private def log_info(message : String)
    @logger.info(log_format(message))
  end

  private def log_error(message : String)
    @logger.error(log_format(message))
  end

  private def log_fatal(message : String)
    @logger.fatal(log_format(message))
  end
end
