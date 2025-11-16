require "./spec_helper"

describe Pom do
  it "has version" do
    Pom::VERSION.should_not be_nil
  end
end
