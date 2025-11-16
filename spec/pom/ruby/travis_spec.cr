describe Pom::Ruby::Travis do
  it "rubies" do
    Pom::Ruby::Travis.rubies.should_not be nil
  end

  # it "print_rubies" do
  #   Pom::Ruby::Travis.print_rubies.should be nil
  # end
end
