module Garager
  class ConfigBuilder < OptStruct.new
    def self.out(env)
      self.new(env: env).perform
    end

    option :env, "development"
    option :dir, CONFIG_DIR
    option :key, -> { generate_new_key }

    def perform
      config_data = {
        private_key: key.to_s,
        public_key: key.public_key.to_s,
        uri: "ws://localhost:3333/cable",
        device_id: "garage #{Random.hex(2)}"
      }.merge(options.except(:env, :path, :key))
      File.write(
        File.join(dir, "#{env}.yaml"),
        config_data.transform_keys(&:to_s).to_yaml
      )
    end

    private

    def generate_new_key
      OpenSSL::PKey::RSA.generate(2048)
    end
  end
end
