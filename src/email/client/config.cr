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

  def self.create_default_logger(log_io : IO = STDOUT) : Logger
    logger = Logger.new(log_io)
    logger.progname = EMail::Client::LOG_PROGNAME
    logger.formatter = EMail::Client::LOG_FORMATTER
    logger.level = Logger::INFO
    logger
  end

  class Config
    property host : String
    property port : Int32
    getter name = EMail::Client::DEFAULT_NAME
    property logger : Logger = EMail::Client.create_default_logger
    getter helo_domain : String?
    property on_failed : EMail::Client::OnFailedProc?
    property on_fatal_error : EMail::Client::OnFatalErrorProc?
    @tls = false
    property openssl_verify_mode = OpenSSL::SSL::VerifyMode::PEER
    @auth : NamedTuple(id: String, password: String)?
    getter dns_timeout : Int32?
    getter connect_timeout : Int32?
    getter read_timeout : Int32?
    getter write_timeout : Int32?

    def self.create(host, port = EMail::DEFAULT_SMTP_PORT, *,
                    client_name name = nil, helo_domain = nil,
                    on_failed : EMail::Client::OnFailedProc? = nil,
                    on_fatal_error : EMail::Client::OnFatalErrorProc? = nil,
                    openssl_verify_mode : OpenSSL::SSL::VerifyMode? = nil,
                    use_tls : Bool? = nil, auth : Tuple(String, String)? = nil,
                    logger : Logger? = nil,
                    log_io : IO? = nil, log_level : Logger::Severity? = nil,
                    log_progname : String? = nil, log_formatter : Logger::Formatter? = nil,
                    dns_timeout : Int32? = nil, connect_timeout : Int32? = nil,
                    read_timeout : Int32? = nil, write_timeout : Int32? = nil)
      config = new(host, port)
      config.name = name if name
      config.helo_domain = helo_domain if helo_domain
      config.on_failed = on_failed if on_failed
      config.on_fatal_error = on_fatal_error if on_fatal_error
      config.openssl_verify_mode = openssl_verify_mode if openssl_verify_mode
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

    def helo_domain=(new_domain : String)
      raise EMail::Error::ClientConfigError.new("Invalid HELO domain \"#{helo_domain}\"") unless new_domain =~ DOMAIN_FORMAT
      @helo_domain = new_domain
    end

    def use_tls(tls_port : Int32? = nil)
      {% if flag?(:without_openssl) %}
      raise EMail::Error::ClientConfigError.new("TLS is disabled because `-D without_openssl` was passed at compile time")
      {% end %}
      @port = tls_port if tls_port
      @tls = true
    end

    def use_tls?
      @tls
    end

    def name=(new_name : String)
      raise EMail::Error::ClientConfigError.new("Invalid client name \"#{new_name}\"") if new_name.empty? || new_name =~ /\W/
      @name = new_name
    end

    def use_auth(id, password)
      @auth = {id: id, password: password}
    end

    def auth_id
      @auth.try &.[](:id)
    end

    def auth_password
      @auth.try &.[](:password)
    end

    def use_auth?
      !@auth.nil?
    end

    {% for name in ["dns", "connect", "read", "write"] %}
    def {{name.id}}_timeout=(sec : Int32)
      raise EMail::Error::ClientConfigError.new("{{name.id}}_timeout must be greater than 0.") unless sec > 0
      @{{name.id}}_timeout = sec
    end
    {% end %}
  end
end
