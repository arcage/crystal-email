require "./spec_helper"

describe EMail do

  descrive EMail::Address do
    it "rejects invalid email address" do
      EMail::Address.new("aaa@ww.bbcc,cc")
    end
  end
end
