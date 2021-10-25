# Thanks to https://github.com/TobiasBales/nixos-m1-arm-builder/ for
# the original source that this is based on.

FROM ubuntu:21.10

# install dependencies
RUN apt update -y
RUN apt install curl sudo xz-utils -y

# use bash instead of sh to be able to source nix configuration
SHELL ["/bin/bash", "-c"]

# create nix user and grant passwordless sudo rights for nix installation
RUN useradd -ms /bin/bash nix
RUN echo "nix ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/100-nix
USER nix
WORKDIR /home/nix

# install nix and set environment
RUN curl -L https://nixos.org/nix/install | sh
RUN source /home/nix/.nix-profile/etc/profile.d/nix.sh
ENV PATH /home/nix/.nix-profile/bin:$PATH
ENV NIX_PATH /home/nix/.nix-defexpr/channels

# This bug still repros with 21.05, but if you want to use 21.05 rather
# than unreleased NixOS you can uncomment the below:
#ENV NIX_PATH /home/nix/.nix-defexpr/channels/nixos-21.05
#RUN nix-channel --add http://nixos.org/channels/nixos-21.05 nixos-21.05
#RUN nix-channel --update

COPY ./iso.nix /home/nix/iso.nix
RUN sudo chown nix:nix /home/nix/iso.nix

# generate nix iso
RUN nix-build '<nixpkgs/nixos>' -A config.system.build.isoImage -I nixos-config=iso.nix

RUN cp $(find /home/nix/result/iso/nixos-*.iso) /tmp/nixos.iso
