class EMail::Client
  # SMTP error handler.
  #
  # Called when the SMTP server returns **4XX** or **5XX** responce during sending email.
  alias OnFailedProc = Message, Array(String) ->

  # Fatal error handler.
  #
  # Called when the exception is raised during sending email.
  alias OnFatalErrorProc = Exception ->

  LOG_FORMATTER = Logger::Formatter.new do |severity, datetime, progname, message, io|
    io << datetime.to_s("%Y/%m/%d %T") << " [" << progname << "/" << Process.pid << "] "
    io << severity << " " << message
  end
  LOG_PROGNAME                = "crystal-email"
  DEFAULT_NAME                = "EMail_Client"
  DEFAULT_FATAL_ERROR_HANDLER = OnFatalErrorProc.new do |e|
    if backtrace = e.backtrace?
      backtrace.each do |line|
        STDERR << "  from " << line << '\n'
      end
    end
    exit(1)
  end

  # SMTP client settings.
  #
  # ```crystal
  # # Set the SMTP server FQDN(or IP address) and port.
  # config = EMail::Client::Config.new("your.mx.example.com", 587)
  #
  # # Set domain name for SMTP HELO/EHLO command.
  # # Default: "[#{IP address of client host}]"
  # config.helo_domain = "your.host.example.com"
  #
  # # Set email client name.
  # # Default: "EMail_Client"
  # config.name = "your_app_name"
  #
  # # Use STARTTLS command to send email
  # config.use_tls
  #
  # # OpenSSL::SSL::Context::Client object for STARTTLS commands.
  # config.tls_context
  #
  # # # Disable TLS1.1 or lower protocols.
  # config.tls_context.add_options(OpenSSL::SSL::Options::NO_SSL_V2 | OpenSSL::SSL::Options::NO_SSL_V3 | OpenSSL::SSL::Options::NO_TLS_V1 | OpenSSL::SSL::Options::NO_TLS_V1_1)
  #
  # # # Set OpenSSL verification mode to skip certificate verification.
  # # # #openssl_verify_mode= method is deprecated now.
  # config.tls_context.verify_mode = OpenSSL::SSL::VerifyMode::NONE
  #
  # # Use SMTP AUTH for user authentication.
  # config.use_auth("id", "password")
  #
  # # Use crystal default Logger object to output logs to STDOUT.
  # config.logger = Logger.new(STDOUT)
  #
  # # Set SMTP error handler.
  # # Default: nil
  # config.on_failed = EMail::Client::OnFailedProc.new do |mail, command_history|
  #   puts mail.data
  #   puts ""
  #   puts command_history.join("\n")
  # end
  #
  # # Set fatal error handler.
  # # Default: DEFAULT_FATAL_ERROR_HANDLER
  # config.on_fatal_error = EMail::Client::OnFatalErrorProc.new do |error|
  #   puts error
  # end
  #
  # # Set connection timeout to 1 sec.
  # config.connect_timeout = 1
  # ```
  #
  # ### Debug log
  #
  # When you set the log level to `Logger::Severity::DEBUG`, you can see all of the SMTP commands and the resposes in the log entries.
  #
  # ```crystal
  # config.logger.level = Logger::Severity::DEBUG
  # ```
  #
  # Debug log are very useful to check how SMTP session works.
  #
  # But, in the case of using SMTP AUTH, the debug log includes Base64 encoded user ID and passowrd. You should remenber that anyone can decode the authentication information from the debug log. And, you should use that very carefully.
  #
  class Config
    # SMTP server hostname or IP address.
    property host : String

    # Port number of SMTP server.
    property port : Int32

    # Client name used in **Message-Id** header and log entry.
    getter client_name = EMail::Client::DEFAULT_NAME

    # Domain name for SMTP **HELO** / **EHLO** command.
    getter helo_domain : String?

    # Logger object for logging SMTP session.
    property logger : Logger = EMail::Client::Config.create_default_logger

    # Callback function to be called when the SMTP server returns **4XX** or **5XX** response.
    #
    # This will be called with email message object that tried to send, and SMTP commands and responses history. In this function, you can do something to handle errors: e.g. "investigating the causes of the fail", "notifying you of the fail", and so on.Fatal error handler.
    property on_failed : EMail::Client::OnFailedProc?

    # Callback function to be calld when an exception is raised during SMTP session.
    #
    # It will be called with the raised Exception instance.
    property on_fatal_error : EMail::Client::OnFatalErrorProc = DEFAULT_FATAL_ERROR_HANDLER

    # OpenSSL context for the TLS connection
    #
    # See [OpenSSL::SSL::Context::Client](https://crystal-lang.org/api/OpenSSL/SSL/Context/Client.html).
    getter tls_context = OpenSSL::SSL::Context::Client.new

    # Sets OpenSSL verification mode for the TLS connection.
    @[Deprecated("use #tls_context.verify_mode=")]
    def openssl_verify_mode=(verify_mode : OpenSSL::SSL::VerifyMode)
      @tls_context.verify_mode = verify_mode
    end

    # Gets OpenSSL verification mode for the TLS connection.
    @[Deprecated("use #tls_context.verify_mode")]
    def openssl_verify_mode : OpenSSL::SSL::VerifyMode
      @tls_context.verify_mode
    end

    # DNS timeout for the socket.
    getter dns_timeout : Int32?

    # CONNECT timeout for the socket.
    getter connect_timeout : Int32?

    # READ timeout for the socket.
    getter read_timeout : Int32?

    # WRITE timeout for the socket.
    getter write_timeout : Int32?

    @tls = false
    @auth : NamedTuple(id: String, password: String)?

    # :nodoc:
    def self.create_default_logger(log_io : IO? = STDOUT) : Logger
      logger = Logger.new(log_io)
      logger.progname = EMail::Client::LOG_PROGNAME
      logger.formatter = EMail::Client::LOG_FORMATTER
      logger.level = Logger::INFO
      logger
    end

    @[Deprecated("use **tls_verify_mode** argument instead of **openssl_verify_mode**.")]
    def self.create(host, port = EMail::DEFAULT_SMTP_PORT, *,
                    client_name = nil, helo_domain = nil,
                    on_failed : EMail::Client::OnFailedProc? = nil,
                    on_fatal_error : EMail::Client::OnFatalErrorProc? = nil,
                    openssl_verify_mode : OpenSSL::SSL::VerifyMode,
                    use_tls : Bool? = nil, auth : Tuple(String, String)? = nil,
                    logger : Logger? = nil,
                    log_io : IO? = nil, log_level : Logger::Severity? = nil,
                    log_progname : String? = nil, log_formatter : Logger::Formatter? = nil,
                    dns_timeout : Int32? = nil, connect_timeout : Int32? = nil,
                    read_timeout : Int32? = nil, write_timeout : Int32? = nil)
      create(host, port, client_name: client_name, helo_domain: helo_domain, on_failed: on_failed, on_fatal_error: on_fatal_error, tls_verify_mode: openssl_verify_mode, use_tls: use_tls, auth: auth, logger: logger, log_io: log_io, log_level: log_level, log_progname: log_progname, log_formatter: log_formatter, dns_timeout: dns_timeout, connect_timeout: connect_timeout, read_timeout: read_timeout, write_timeout: write_timeout)
    end

    # Returns `EMail::Client::Config` object with given settings.
    #
    # - `use_tls: true` -> `#use_tls`
    # - `auth: {"id", "password"}` -> `#use_auth("id", "password")`
    #
    # When other optional arguments are given, the property that has same name will be set.
    #
    # **NOTE: The `logger` option and `log_XXX` options are exclusive.**
    def self.create(host, port = EMail::DEFAULT_SMTP_PORT, *,
                    client_name = nil, helo_domain = nil,
                    on_failed : EMail::Client::OnFailedProc? = nil,
                    on_fatal_error : EMail::Client::OnFatalErrorProc? = nil,
                    tls_verify_mode : OpenSSL::SSL::VerifyMode? = nil,
                    use_tls : Bool? = nil, auth : Tuple(String, String)? = nil,
                    logger : Logger? = nil,
                    log_io : IO? = nil, log_level : Logger::Severity? = nil,
                    log_progname : String? = nil, log_formatter : Logger::Formatter? = nil,
                    dns_timeout : Int32? = nil, connect_timeout : Int32? = nil,
                    read_timeout : Int32? = nil, write_timeout : Int32? = nil)
      config = new(host, port)
      config.client_name = client_name if client_name
      config.helo_domain = helo_domain if helo_domain
      config.on_failed = on_failed if on_failed
      config.on_fatal_error = on_fatal_error if on_fatal_error
      config.tls_context.verify_mode = tls_verify_mode if tls_verify_mode
      config.use_tls if use_tls
      config.use_auth(auth[0], auth[1]) if auth
      if logger
        raise EMail::Error::ClientConfigError.new("Cannot set `logger` and `log_*` at the same time.") if log_io || log_level || log_progname || log_formatter
        config.logger = logger if logger
      else
        config.logger = create_default_logger(log_io) if log_io
        config.logger.level = log_level if log_level
        config.logger.progname = log_progname if log_progname
        config.logger.formatter = log_formatter if log_formatter
      end
      config.dns_timeout = dns_timeout if dns_timeout
      config.connect_timeout = connect_timeout if connect_timeout
      config.read_timeout = read_timeout if read_timeout
      config.write_timeout = write_timeout if write_timeout
      config
    end

    def initialize(@host, @port = EMail::DEFAULT_SMTP_PORT)
    end

    # Domain name for SMTP **HELO** or **EHLO** command.
    #
    # Only FQDN format is acceptable.
    def helo_domain=(new_domain : String)
      raise EMail::Error::ClientConfigError.new("Invalid HELO domain \"#{helo_domain}\"") unless new_domain =~ DOMAIN_FORMAT
      @helo_domain = new_domain
    end

    #
    def use_tls(tls_port : Int32? = nil)
      {% if flag?(:without_openssl) %}
        raise EMail::Error::ClientConfigError.new("TLS is disabled because `-D without_openssl` was passed at compile time")
      {% end %}
      @port = tls_port if tls_port
      @tls = true
    end

    # Returns `true` when using TLS.
    def use_tls?
      @tls
    end

    # Client name used in **Message-ID** header and log entry.
    #
    # Only alphabets(`a`-`z`, `A`-`Z`), numbers(`0`-`9`), and underscore(`_`) are acceptable.
    def client_name=(new_name : String)
      raise EMail::Error::ClientConfigError.new("Invalid client name \"#{new_name}\"") if new_name.empty? || new_name =~ /\W/
      @client_name = new_name
    end

    # Set the client to authenticate with SMTP **AUTH** command by using given id and password.
    #
    # Only **AUTH PLAIN** and **AUTH LOGIN** commands are supported.
    #
    # **NOTE: SMTP authentication can be used only under TLS encryption.**
    def use_auth(id, password)
      @auth = {id: id, password: password}
    end

    # Returns authentication id when using SMTP AUTH.
    def auth_id
      @auth.try &.[](:id)
    end

    # Returns authentication password when using SMTP AUTH.
    def auth_password
      @auth.try &.[](:password)
    end

    # Returns `true` when using SMTP AUTH.
    def use_auth?
      !@auth.nil?
    end

    {% for name in ["dns", "connect", "read", "write"] %}
    # {{name.id.upcase}} timeout for the socket.
    def {{name.id}}_timeout=(sec : Int32)
      raise EMail::Error::ClientConfigError.new("{{name.id}}_timeout must be greater than 0.") unless sec > 0
      @{{name.id}}_timeout = sec
    end
    {% end %}
  end
end
