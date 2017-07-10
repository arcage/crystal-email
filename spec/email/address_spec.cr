require "../spec_helper"

describe EMail::Address do
  describe ".valid_address!" do
    it "returns argument when it seems to be a valid email address" do
      EMail::Address.valid_address!("aa@bb.cc").should eq "aa@bb.cc"
    end

    it "raises Email::Error::AddressError when argument seems to be invalid as a email address" do
      expect_raises(EMail::Error::AddressError) {
        EMail::Address.valid_address!("aa@bb,cc")
      }
    end
  end

  describe ".valid_name!" do
    it "returns argument when it inclued no line breaks" do
      EMail::Address.valid_name!("John Doe").should eq "John Doe"
    end

    it "raises Email::Error::AddressError when argument includes line break" do
      expect_raises(EMail::Error::AddressError) {
        EMail::Address.valid_name!("John\nDoe")
      }
    end
  end

  describe ".new" do
    it "rejects provably invalid email address" do
      expect_raises(EMail::Error::AddressError) {
        EMail::Address.new("aa@bb,cc")
      }
    end

    it "rejects sender name that includes line break" do
      expect_raises(EMail::Error::AddressError) {
        EMail::Address.new("aa@bb.cc", "John\nDoe")
      }
    end
  end

  describe "#to_s" do
    it "returns only address string when without sender name" do
      EMail::Address.new("aa@bb.cc").to_s.should eq "aa@bb.cc"
    end

    it "returns sender name and angled address string when sender name exists" do
      EMail::Address.new("aa@bb.cc", "John Doe").to_s.should eq "John Doe <aa@bb.cc>"
    end
  end
end
