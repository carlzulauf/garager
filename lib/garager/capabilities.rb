module Garager
  class Capabilities
    def self.standard_garage
      new.standard_garage
    end

    def standard_garage
      [
        action(:toggle, desc: "Open garage if closed. Close it if open."),
        status_image(:camera, desc: "Most recent image from the garage controller's camera."),
        status(:presumed_state, desc: "Best guess about whether garage is open or closed.", default: "closed"),
        action(:update_camera, desc: "Refresh status image right now"),
        action(:air_out, desc: "Open the garage for 5 minutes, then close it"),
        action(:delayed_toggle, desc: "Close (or Open) the garage after the specified number of minutes", default: "5", type: "action_with_param"),
        # action(:set_open, desc: "If the garage is really open but this software says it's closed, press this."),
        # action(:set_closed, desc: "If the garage is really closed but this software says it's open, press this."),
      ]
    end

    private

    def action(name, desc:, **extra)
      { type: "action", name: name, description: desc }.merge(extra)
    end

    def output_stream(name, desc: nil)
      { type: "output_stream", name: name }.tap do |o|
        o[:description] = desc if desc
      end
    end

    def status(name, desc: nil, default: nil)
      { type: "status", name: name }.tap do |o|
        o[:description] = desc    if desc
        o[:default]     = default if default
      end
    end

    def status_image(name, desc: nil)
      { type: "status_image", name: name }.tap do |o|
        o[:description] = desc if desc
      end
    end
  end
end
