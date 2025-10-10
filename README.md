# Neomutt for Gmail

Neomutt is great to burn through email really fast. When email was hosted on disperate servers, we would all smash together sendmail, postfix and debate between `mbox` and `Maildir` formats. Imap was a great evolution to keep the data on the server, but for those of us using gmail, imap is a second class citizen.

There have been some really nice initiatives to make things easier for those who want to access massive repositories of email, while using gmail (or Google Workspace) as your email provider.

- [Lieer](https://github.com/gauteh/lieer) - Uses the Google APIs for fetching, send email, managing labels and stuff
- [Notmuch](https://github.com/notmuch/notmuch) - A lightweight database designed for managing email and making searching for stuff FAST. 
- [Neomutt](https://gnithub.com/neomutt/neomutt) - The evoluation of the original `mutt` client with a bunch of features. Can use `notmuch` as the backend for email.
- [Mutt-Wizard](https://github.com/LukeSmithxyz/mutt-wizard) - A really sophisticated system for getting a neomutt setup. Leveraging the keybindings here.

Years ago, getting all these to play nicely together took many hours of work. **This repo is an effort to make it as turn key as possible to get you using neomutt with your gmail account**.

## Opinions

- *Linux only (for now) - Lieer isn't really setup for Mac it seems.
-  Instead of a stack of instructions for you to follow, [Home Manager](https://github.com/nix-community/home-manager) (A system and dot file generator for any linux or darwin based system) has a lot of work in tying the above systems together. This repo takes it further with intelligent defaults for gmail.
- *Plaintext is dead* - Let's face it, no one sends plaintext anymore. This repo embraces the reality that HTML is the standard. Thankfully, [muttdown](https://github.com/jevy/muttdown) let's us work in markdown, and when we send our email, "mark it up" to HTML.
- *Minimally functional as possible* - I don't want to have to spend a ton of time maintaining this. Thankfully home-manager has done most of the work to make the configuration pretty easy. That said, because we are using Nix, you can extend/overwrite whatever you want.

## Quick Start

### 1. Install Nix (5 minutes)

Practically, Nix is really a nice, functional language that will build packages into isolated directories and use symlinks to connect them into your system. It has the [largest repository of packages}(https://repology.org/repositories/statistics/total) (eat it Arch!).

The best way is to install [Determinate System's Nix Installer](https://github.com/DeterminateSystems/nix-installer). 

### 2. Configure your home manager email setup

Below is an example "flake" (like a declarative combinations of both dot file configs and packages) that will:

- Pull in `home-manager` - This has all the modules and configuration for lieer, neomutt, notmuch etc.
- Pull in `neomutt-gmail` - The repo you're looking at here. It wires together the `home-manager` setup for `gmail`/`google workspace` defaults.

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    neomutt-gmail.url = "github:jevy/neomutt-for-gmail";
  };

  outputs = { nixpkgs, home-manager, neomutt-gmail, ... }: {
    homeConfigurations.yourusername = home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
      
      modules = [
        neomutt-gmail.homeManagerModules.default
        
        {
          home.username = "yourusername";
          home.homeDirectory = "/home/yourusername";
          home.stateVersion = "25.04";
          
          programs.home-manager.enable = true;
          
          services.lieer.enable = true;
          
          accounts.email.accounts.gmail = {
            address = "your-email@gmail.com";
            userName = "your-email@gmail.com";
            flavor = "gmail.com";
            passwordCommand = "pass show email/gmail";
            realName = "Your Name";
            primary = true;
            maildir.path = "gmail";
            
            lieer = {
              enable = true;
              sync = {
                enable = true;
                frequency = "*:0/5";
              };
            };
            
            notmuch.enable = true;
            msmtp.enable = true;
            neomutt.enable = true;
          };
        }
      ];
    };
  };
}
```

### 3. Activate your configuration

TODO: Gotta confirm this

```bash
home-manager switch --flake .#yourusername
```

### 4. Set up Gmail API credentials

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project
3. Enable the Gmail API
4. Create OAuth2 credentials (Desktop application)
5. Download the credentials JSON file

### 5. Bootstrap notmuch

```bash
cd ~/Maildir
notmuch new
```

### 5. Bootstrap lieer to build the `.gmailieer.json` config

```bash
cd ~/Maildir/gmail
gmi init your-email@gmail.com
gmi sync
```

### 6. That's it! Launch neomutt

```bash
neomutt
```


## Customization

You can override or extend any settings:

Either in the [extraConfig](https://nix-community.github.io/home-manager/options.xhtml#opt-accounts.email.accounts._name_.neomutt.extraConfig) or in the home manager setup directly

```nix
{
  programs.neomutt.settings = {
    sort = "date";
    index_format = "%4C %Z %{%Y-%m-%d} %-15.15L %s";
  };
  
  programs.neomutt.sidebar.width = 30;
  
  programs.neomutt.extraConfig = ''
    color index brightblue default "~N"
  '';
}
```


## Testing

Want to test the setup without affecting your main system? Use the included VM configuration:

### 1. Generate `.gmaileer.json` locally.

The VM doesn't have a browser to do the oauth stuff. So you do the work on your local machine (in any dir).

1. `gmi init youremail@gmail.com` on your machine
2. Then `cp .credentials.gmaileer.json ./vm-test/` 

### 2. Run the VM

```bash
# Build and run the test VM
nix build ./vm-test#nixosConfigurations.vm-test.config.system.build.vm
./result/bin/run-*-vm
```

The VM includes:
- Pre-configured neomutt-gmail setup
- Test Gmail account with failing credentials
- All necessary packages installed
- Isolated environment for testing

See [TESTING.md](./TESTING.md) for more testing options.

## TODOs

- [ ] Clean up some keybindings
- [ ] Better themes
