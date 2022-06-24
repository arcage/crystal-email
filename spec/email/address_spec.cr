require "../spec_helper"

describe NetUtils::EMail::Address do
  describe ".valid_address!" do
    it "returns argument when it seems to be a valid email address" do
      NetUtils::EMail::Address.valid_address!("aa@bb.cc").should eq "aa@bb.cc"
    end

    it "accepts domain part without \".\"" do
      NetUtils::EMail::Address.valid_address!("aa@localhost").should eq "aa@localhost"
    end

    it "raises Email::AddressError when argument seems to be invalid as a email address" do
      expect_raises(NetUtils::EMail::AddressError) {
        NetUtils::EMail::Address.valid_address!("aa@bb,cc")
      }
    end
  end

  describe ".valid_name!" do
    it "returns argument when it inclued no line breaks" do
      NetUtils::EMail::Address.valid_name!("John Doe").should eq "John Doe"
    end

    it "raises Email::AddressError when argument includes line break" do
      expect_raises(NetUtils::EMail::AddressError) {
        NetUtils::EMail::Address.valid_name!("John\nDoe")
      }
    end
  end

  describe ".new" do
    it "rejects provably invalid email address" do
      expect_raises(NetUtils::EMail::AddressError) {
        NetUtils::EMail::Address.new("aa@bb,cc")
      }
    end

    it "rejects sender name that includes line break" do
      expect_raises(NetUtils::EMail::AddressError) {
        NetUtils::EMail::Address.new("aa@bb.cc", "John\nDoe")
      }
    end
  end

  describe "#to_s" do
    it "returns only address string when without sender name" do
      NetUtils::EMail::Address.new("aa@bb.cc").to_s.should eq "aa@bb.cc"
    end

    it "returns sender name and angled address string when sender name exists" do
      NetUtils::EMail::Address.new("aa@bb.cc", "John Doe").to_s.should eq "John Doe <aa@bb.cc>"
    end
  end
end
