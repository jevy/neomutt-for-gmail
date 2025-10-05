# Testing Guide

This guide explains how to safely test the neomutt-gmail flake without affecting your main system.

## Option 1: NixOS VM (Safest)

Use the included VM test flake to test the complete setup in an isolated environment:

Build and run:
```bash
nix build ./vm-test#nixosConfigurations.vm-test.config.system.build.vm
./result/bin/run-*-vm
```

Inside the VM, you can test the neomutt setup with failing credentials:
```bash
# Login as testuser (password: test)
su - testuser

# Check the Mail directory structure
ls -la ~/Mail/
ls -la ~/Mail/gmail/

# Initialize lieer (required before systemd service can run)
cd ~/Mail/gmail
gmi init test-email@gmail.com

# Try to authenticate (will fail due to invalid credentials - expected)
gmi auth

# Check lieer systemd services (they will fail until gmi auth succeeds)
systemctl --user list-timers | grep lieer
systemctl --user status lieer-gmail.service
systemctl --user status lieer-gmail.timer

# View lieer service logs (will show authentication errors)
journalctl --user -u lieer-gmail.service -f
# Or view all logs:
journalctl --user -u lieer-gmail.service --no-pager

# Manually trigger a sync to see the error
gmi sync

# Launch neomutt to see the configuration
neomutt
```

**Note**: The lieer systemd service will fail until you successfully run `gmi auth` with valid credentials. This is expected behavior for the test environment with invalid credentials.

The VM comes pre-configured with:
- The neomutt-gmail flake imported and configured
- A test Gmail account (`test-email@gmail.com`) with invalid credentials
- All necessary packages (neomutt, lieer, notmuch, muttdown)
- 2GB RAM and 2 CPU cores

This allows you to test the setup flow without affecting real accounts or your main system.

## Option 2: Docker/Podman Container

Create a container with Nix:

```bash
docker run -it nixos/nix

nix-channel --add https://github.com/nix-community/home-manager/archive/master.tar.gz home-manager
nix-channel --update

nix-shell '<home-manager>' -A install
```

Then test your flake inside the container. The systemd timers won't interfere with your host.

## Option 3: Separate Home-Manager Profile (Careful!)

You can create a test profile that won't affect your main home-manager setup:

```bash
mkdir -p ~/test-neomutt
cd ~/test-neomutt

cat > flake.nix << 'EOF'
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    neomutt-gmail.url = "path:/home/jevin/code/personal/neomutt-for-gmail";
  };

  outputs = { nixpkgs, home-manager, neomutt-gmail, ... }: {
    homeConfigurations.test = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      
      modules = [
        neomutt-gmail.homeManagerModules.default
        {
          home.username = "testuser";
          home.homeDirectory = "/tmp/test-home";
          home.stateVersion = "23.11";
          
          programs.home-manager.enable = true;
          
          accounts.email.accounts.gmail = {
            address = "test@gmail.com";
            userName = "test@gmail.com";
            flavor = "gmail.com";
            passwordCommand = "echo 'dummy'";
            realName = "Test User";
            primary = true;
            maildir.path = "gmail";
            
            lieer.enable = true;
            notmuch.enable = true;
            msmtp.enable = true;
            neomutt.enable = true;
          };
        }
      ];
    };
  };
}
EOF

mkdir -p /tmp/test-home
HOME=/tmp/test-home home-manager switch --flake .#test
```

**Warning**: This still creates systemd user services, but they'll be isolated to the test user.

## Option 4: Dry Run Build (Safest for Quick Check)

Just build without activating:

```bash
nix build .#homeConfigurations.test.activationPackage
```

This will:
- Check that the flake builds correctly
- Verify all dependencies resolve
- Show you what would be installed
- NOT activate anything or create systemd services

Then inspect the result:
```bash
ls -la result/
cat result/activate
```

## Option 5: Check Systemd Services Before Activating

Before running `home-manager switch`, you can see what systemd services will be created:

```bash
nix build .#homeConfigurations.test.activationPackage
grep -r "systemd" result/
```

Look for timer and service files related to lieer.

## Recommended Testing Flow

1. **First**: Use Option 4 (dry run build) to verify the flake builds
2. **Then**: Use Option 1 (VM) or Option 2 (container) for full integration testing
3. **Finally**: Test on your actual system with a backup of your home-manager config

## Checking for Systemd Conflicts

Before activating, check what systemd services are currently running:

```bash
systemctl --user list-timers
systemctl --user list-units | grep lieer
```

After activation in a test environment, verify the new services:

```bash
systemctl --user list-timers | grep lieer
systemctl --user status lieer-gmail.timer
systemctl --user status lieer-gmail.service
```

## Cleaning Up Test Environment

If you used Option 3 (separate profile):

```bash
systemctl --user stop lieer-gmail.timer
systemctl --user disable lieer-gmail.timer
rm -rf /tmp/test-home
```

## What Gets Created

When you activate this flake, home-manager will create:

1. **Config files**:
   - `~/.config/neomutt/neomuttrc`
   - `~/.gmailieer.json` (in each maildir)
   - `~/.notmuch-config`

2. **Systemd user services** (if lieer sync is enabled):
   - `lieer-<account>.service`
   - `lieer-<account>.timer`

3. **Directories**:
   - `~/Mail/<account>/` (maildir)

These won't conflict with existing setups unless you already have:
- A neomutt config at `~/.config/neomutt/neomuttrc`
- Lieer systemd services with the same name
- A notmuch database at `~/.local/share/notmuch`

## Safe Testing Checklist

- [ ] Backup your current home-manager configuration
- [ ] Check for existing lieer systemd services
- [ ] Verify no conflicting neomutt config exists
- [ ] Test in VM or container first
- [ ] Review the activation script before running
- [ ] Have a rollback plan ready

## Rollback

If something goes wrong after activation:

```bash
home-manager generations
home-manager switch --switch-generation <number>
```

Or restore from your backup.