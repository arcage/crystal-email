
class EMail::Error < Exception

  class InvalidMailAddress < Error
    def initialize(address : ::String)
      super(address.inspect)
    end
  end

  class InvalidMailName < Error
    def initialize(name : ::String?)
      super(name.inspect)
    end
  end

  class InvalidHeaderName < Error
    def initialize(name : ::String)
      super(name.inspect)
    end
  end

  class InvalidLineBreak < Error
    def initialize(line : ::String)
      super(line.inspect)
    end
  end

  class AttachedFileNotFound < Error
    def initialize(path : ::String)
      super(path.inspect)
    end
  end

  class ClientError < Error
  end

  class InvalidMessage < Error
  end

end
