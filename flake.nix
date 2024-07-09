{
  description = "A very basic flake";

  # Cache to reduce build times dont worry about it
  nixConfig = {
    extra-substituters = [ "https://raspberry-pi-nix.cachix.org" ];
    extra-trusted-public-keys = [
      "raspberry-pi-nix.cachix.org-1:WmV2rdSangxW0rZjY/tBvBDSaNFQ3DyEQsVw8EvHn9o="
    ];
  };

  # All the outside things to fetch from the internet
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    raspberry-pi-nix.url = "github:tstat/raspberry-pi-nix";
  };

  outputs = { self, nixpkgs, raspberry-pi-nix }: rec {
    # shoutout to https://github.com/tstat/raspberry-pi-nix absolute goat
    shared_config = {
      #target architecture
      nixpkgs.hostPlatform.system = "aarch64-linux";

      #NTP
      services.timesyncd.enable = true;

      # Disable signatures
      nix.settings.require-sigs = false;

      # user setup; creates user named nixos and sets up passwords
      users.users.root.initialPassword = "root";
      users.users.nixos.group = "nixos";
      users.users.nixos.password = "nixos";
      users.users.nixos.extraGroups = [ "wheel" ];
      users.users.nixos.isNormalUser = true;

      system.activationScripts.createRecordingsDir = nixpkgs.lib.stringAFter ["users"] ''
      mkdir -p /home/nixos/recordings
      chown nixos:users /home/nixos/recordings
      '';

      # Network settings
      networking.hostName = "Philipp";

      networking.firewall.enable = false;
      networking.useDHCP = false;

      # SSH settings
      services.openssh = { enable = true; };

      users.extraUsers.nixos.openssh.authorizedKeys.keys = [ ];

      systemd.services.sshd.wantedBy =
        nixpkgs.lib.mkOverride 40 [ "multi-user.target" ];

    };

    nixosConfigurations.rpi = nixpkgs.lib.nixosSystem {
      system = "aarch64-linux";
      modules = [
        (
          { pkgs, ... }: {
            config = {
              # Utils and other apps you want
              environment.systemPackages = with pkgs; [
                can-utils
                iperf3
              ];

              # Settings for the image that is generated
              sdImage.compressImage = false;
              raspberry-pi-nix.uboot.enable = false;
            };

            # Start the logging service
            options = {
              services.data_writer.options.enable = true;
            };
          }
        )

        # Getting the RPi firmware
        raspberry-pi-nix.nixosModules.raspberry-pi

        # Running the configs made earlier
        shared_config
      ];
    };

    # Defineing the build commands for the terminal
    images.rpi_sd = nixosConfigurations.rpi.config.system.build.sdImage;
    images.rpi_top = nixosConfigurations.rpi.config.system.build.toplevel;
  };
}
