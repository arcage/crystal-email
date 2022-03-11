require "./client/*"
require "log"

# SMTP client object.
#
# ### Client configuration
#
# EMail::Client::Config object is used to set client configrations.
#
# ### Logging
#
# Without client specific logger in EMail::Client::Config, all EMail::Client objects use the default logger.
#
# The default logger can be got by EMail::Client.log
# You can set log level, output IO, and log formatter for the default logger by using EMail::Client.log_level=, EMail::Client.log_io=, EMail::Client.log_formatter= methods respectively.
#
class EMail::Client
  # :nodoc:
  DEFAULT_NAME = "EMail_Client"

  # :nodoc:
  LOG_FORMATTER = Log::Formatter.new do |entry, io|
    io << entry.timestamp.to_s("%Y/%m/%d %T") << " [" << entry.source << "/" << Process.pid << "] "
    io << entry.severity << " " << entry.message
    if entry.context.size > 0
      io << " -- " << entry.context
    end
    if ex = entry.exception
      io << " -- " << ex.class << ": " << ex
    end
  end

  @@log : Log = create_logger

  # Gets default logger([Log](https://crystal-lang.org/api/OpenSSL/Log.html) type object) to output SMTP log.
  def self.log : Log
    @@log
  end

  # Sets log level for default logger.
  def self.log_level=(new_level : Log::Severity)
    @@log.level = new_level
    nil
  end

  # Sets log io for default logger.
  def self.log_io=(new_io : IO)
    if (log_backend = @@log.backend).is_a?(Log::IOBackend)
      log_backend.io = new_io
    end
    nil
  end

  # Sets log formatter for default logger.
  def self.log_formatter=(new_formatter : Log::Formatter)
    if (log_backend = @@log.backend).is_a?(Log::IOBackend)
      log_backend.formatter = new_formatter
    end
    nil
  end

  # :nodoc:
  private def self.create_logger : Log
    log = Log.for(self, Log::Severity::Info)
    log_backend = Log::IOBackend.new(STDOUT)
    log_backend.formatter = LOG_FORMATTER
    log.backend = log_backend
    log
  end

  @helo_domain : String?
  @started : Bool = false
  @first_send : Bool = true
  @tcp_socket : TCPSocket? = nil
  {% if flag?(:without_openssl) %}
    @socket : TCPSocket? = nil
  {% else %}
    @socket : TCPSocket | OpenSSL::SSL::Socket::Client | Nil = nil
  {% end %}
  @command_history = [] of String
  @esmtp_commands = Hash(String, Array(String)).new { |h, k| h[k] = Array(String).new }
  # :nodoc:
  property number : Int32?

  # Gets cliet config object.
  getter config : EMail::Client::Config

  # Creates smtp client object by EMail::Client::Config object.
  def initialize(@config : EMail::Client::Config, @number = nil)
  end

  private def helo_domain : String
    @helo_domain ||= @config.helo_domain
  end

  private def socket
    if _socket = @socket
      _socket
    else
      raise EMail::Error::ClientError.new("Client socket not opened.")
    end
  end

  # Starts SMTP session.
  #
  # In the block, the default receiver will be `self`.
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

  private def wrap_socket_tls
    {% if flag?(:without_openssl) %}
      log_error("TLS is disabled because `-D without_openssl` was passed at compile time")
      false
    {% else %}
      case tcp_socket = @socket
      when TCPSocket
        log_info("create openssl socket.client")
        tls_socket = OpenSSL::SSL::Socket::Client.new(tcp_socket, @config.tls_context, sync_close: true, hostname: @config.host)
        tls_socket.sync = false
        log_info("Start SMTPS session with #{tls_socket.tls_version}")
        @socket = tls_socket
        true
      when OpenSSL::SSL::Socket::Client
        log_info("socket is already useing TLS.")
        true
      else
        raise Error::ClientError.new("socket is not opened.")
        false
      end
    {% end %}
  end

  private def ready_to_send
    log_info("Start TCP session to #{@config.host}:#{@config.port}")
    tcp_socket = TCPSocket.new(@config.host, @config.port, @config.dns_timeout, @config.connect_timeout)
    if read_timeout = @config.read_timeout
      tcp_socket.read_timeout = read_timeout
    end
    if write_timeout = @config.write_timeout
      tcp_socket.write_timeout = write_timeout
    end
    @socket = @tcp_socket = tcp_socket
    wrap_socket_tls if @config.use_smtps?
  end

  private def mail_validate!(mail : EMail::Message) : EMail::Message
    timestamp = Time.local
    mail.date timestamp
    mail.message_id String.build { |io|
      io << '<' << timestamp.to_unix_ms << '.' << Process.pid
      io << '.' << @config.client_name << '@' << helo_domain << '>'
    }
    mail.validate!
  end

  # Sends a email message
  #
  # You can call this only in the block of the `EMail::Client#start` method.
  # This retruns sending result as Bool(`true` for success, `false` for fail).
  def send(mail : EMail::Message) : Bool
    raise EMail::Error::ClientError.new("Email client has not been started") unless @started
    @command_history.clear
    mail = mail_validate!(mail)
    mail_from = mail.mail_from
    recipients = mail.recipients
    if smtp_rset && smtp_mail(mail_from) && smtp_rcpt(recipients) && smtp_data(mail.data)
      log_info("Successfully sent a message from <#{mail_from.addr}> to #{recipients.size} recipient(s)")
      return true
    else
      log_error("Failed sending message for some reason")
      if on_failed = @config.on_failed
        on_failed.call(mail, @command_history)
      end
      return false
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

  private def log : Log
    @config.log || EMail::Client.log
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
    status_code, status_messages = smtp_command("EHLO", helo_domain)
    if status_code == "250"
      status_messages.each do |status_message|
        message_parts = status_message.strip.split(' ')
        command = message_parts.shift
        @esmtp_commands[command] = message_parts
      end
      true
    elsif status_code == "502"
      status_code, _ = smtp_command("HELO", helo_domain)
      status_code == "250"
    end
  end

  private def smtp_starttls
    if @config.use_starttls?
      status_code, _ = smtp_command("STARTTLS")
      if (status_code == "220")
        wrap_socket_tls
        @esmtp_commands.clear
        return smtp_helo
      else
        false
      end
    else
      true
    end
  end

  private def smtp_auth
    if login_credential = @config.use_auth?
      login_id = @config.auth_id.not_nil!
      login_password = @config.auth_password.not_nil!
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

  private def smtp_mail(mail_from : EMail::Address)
    status_code, _ = smtp_command("MAIL", "FROM:<#{mail_from.addr}>")
    status_code == "250"
  end

  private def smtp_rcpt(recipients : Array(EMail::Address))
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

  private def close_socket
    if _socket = @socket
      _socket.close
      log_info("Close session to #{@config.host}:#{@config.port}")
    end
    @socket = nil
  end

  private def fatal_error(error : Exception)
    log_fatal(error)
    if on_fatal_error = @config.on_fatal_error
      on_fatal_error.call(error)
    end
  end

  private def log_format(message : String)
    String.build do |str|
      str << '[' << @config.client_name
      str << '_' << @number if @number
      str << "] " << message
    end
  end

  private def log_debug(message : String)
    message = log_format(message)
    log.debug { message }
  end

  private def log_info(message : String)
    message = log_format(message)
    log.info { message }
  end

  private def log_error(message : String)
    message = log_format(message)
    log.error { message }
  end

  private def log_fatal(error : Exception)
    message = log_format("Exception raised")
    log.fatal(exception: error) { message }
  end
end
