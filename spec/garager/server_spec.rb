describe "Garager::Server" do
  subject { Garager::Server.new(options) }

  let(:valid_key) { SecureRandom.hex }
  let(:invalid_key) { SecureRandom.hex }
  let(:options) { { keys: [valid_key] } }

  context "when started" do
    before { subject.start }
    after { subject.stop }

    context "with authenticated device" do
      let(:client) { Garager::Client.new(key: valid_key) }
      it "accepts registration" do
        token = client.register
        expect(subject.devices[valid_key].token).to eq(token)
        binding.pry
      end
    end
    context "with unauthenticated devices" do
      let(:client) { Garager::Client.new(key: invalid_key) }
      it "rejects the registration" do
        client.register
        binding.pry
      end
    end
  end

  shared_examples "does not accept connections" do
    it "does not allow any devices to connect"
  end

  context "before started" do
    include_examples "does not accept connections"
  end

  context "after stopped" do
    before do
      subject.start
      sleep 1
      subject.stop
    end
    include_examples "does not accept connections"
  end
end
