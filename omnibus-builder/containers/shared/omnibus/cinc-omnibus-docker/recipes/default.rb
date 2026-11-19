# frozen_string_literal: true

# Keep the builder on the toolchain version requested by the top-level command.
version = ENV.fetch("TOOLCHAIN_VERSION")

cinc_omnibus_builder "default" do
  toolchain_version version
  toolchain_channel :stable
end
