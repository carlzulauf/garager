RSpec.describe Garager::FakeGarage do
  it "exists as a class" do
    expect(described_class).to be_a(Class)
  end

  subject { described_class.new(logger: LOGGER) }

  describe "#toggle" do
    it "toggles #presumed state/value" do
      expect { subject.toggle }.to \
        change { subject.presumed }.from(:closed).to(:open)
      expect { subject.toggle }.to \
        change { subject.presumed }.from(:open).to(:closed)
    end

    it "updates the #last timestamp" do
      expect { subject.toggle }.to change { subject.last }
      expect(subject.last).to be_a(Float)
    end

    it "executes the fake_garage_toggle script" do
      expect(Open3).to \
        receive(:capture2e).
        with("bin/fake_garage_toggle").
        and_call_original
      subject.toggle
    end
  end
end
