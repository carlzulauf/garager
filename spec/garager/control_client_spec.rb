RSpec.describe Garager::ControlClient do
  let(:triggers) { [] }
  subject { described_class.new(logger: LOGGER, triggers: triggers, pong_interval: 0.01) }

  describe "#run" do
    it "returns instead of raising when the server drops the connection" do
      allow(Async::WebSocket::Client).to receive(:connect)
        .and_raise(EOFError, "Could not read frame header!")
      subject.instance_variable_set(:@running, true)
      expect { subject.run }.not_to raise_error
      expect(subject).not_to be_connected
    end
  end

  describe "subscription confirmation" do
    it "registers, then triggers a status resend" do
      expect(subject).to receive(:send_message)
        .with(hash_including(command: "message", data: include('"action":"register"')))
      subject.send(:handle_message, { type: "confirm_subscription" }.to_json)
      expect(triggers).to eq([[:registered]])
    end
  end
end
