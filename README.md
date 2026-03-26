# Neomutt for Gmail

<img width="2805" height="1572" alt="swappy-20260326-073945" src="https://github.com/user-attachments/assets/d1347145-4ff6-4bc8-8ca7-54c04756d711" />


Neomutt is great to burn through email really fast. When email was hosted on disperate servers, we would all smash together sendmail, postfix and debate between `mbox` and `Maildir` formats. Imap was a great evolution to keep the data on the server, but for those of us using gmail, imap is a second class citizen.

There have been some really nice initiatives to make things easier for those who want to access massive repositories of email, while using gmail (or Google Workspace) as your email provider.

- [Lieer](https://github.com/gauteh/lieer) - Uses the Google APIs for fetching, send email, managing labels and stuff
- [Notmuch](https://github.com/notmuch/notmuch) - A lightweight database designed for managing email and making searching for stuff FAST. 
- [Neomutt](https://github.com/neomutt/neomutt) - The evoluation of the original `mutt` client with a bunch of features. Can use `notmuch` as the backend for email.
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
          
          accounts.email.accounts.gmail = {
            address = "your-email@gmail.com";
            flavor = "gmail.com";
            realName = "Your Name";
            primary = true;
          };
        }
      ];
    };
  };
}
```

### 3. Activate your configuration

```bash
home-manager switch --flake .#yourusername
```

This automatically:
- Creates the maildir structure (`~/Maildir/gmail/mail/{cur,new,tmp}`)
- Initializes the notmuch database
- Sets up lieer configuration

### 4. Authenticate with Gmail

Run the first sync manually to complete the OAuth flow:

```bash
cd ~/Maildir/gmail
gmi sync
```

This will open a browser window for Google OAuth authentication. Once you authorize the app, you can `Ctrl-C` — the systemd timer will take over from here.

### 5. That's it! Launch neomutt

```bash
neomutt
```

A systemd timer syncs your mail every 5 minutes using `gmi sync --resume`, so even large mailboxes will incrementally sync across runs. The notmuch index is updated automatically after each sync.


## Customization

All settings use `lib.mkDefault`, so you can override anything. The module uses standard [Home Manager email account options](https://nix-community.github.io/home-manager/options.xhtml#opt-accounts.email.accounts._name_.address), so anything you'd normally configure there works here too.

### Account settings

```nix
accounts.email.accounts.gmail = {
  address = "your-email@gmail.com";
  flavor = "gmail.com";
  realName = "Your Name";
  primary = true;

  # Custom maildir location (default: account name under ~/Maildir)
  maildir.path = "personal-gmail";

  # Sync frequency (default: every 5 minutes)
  lieer.sync.frequency = "*:0/2";  # every 2 minutes

  # Additional labels to ignore from Gmail
  lieer.settings.ignore_remote_labels = ["important" "promotions"];
};
```

### Neomutt UI

Override or extend via [extraConfig](https://nix-community.github.io/home-manager/options.xhtml#opt-accounts.email.accounts._name_.neomutt.extraConfig) or in the home manager setup directly:

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


## Contacts

Contact completion works **out of the box** — press `<Tab>` when composing a To/CC/BCC address to search contacts from your email history (via notmuch), sorted by how frequently you email them.

Optionally, you can connect **Google Contacts** to also pull in contacts you haven't emailed yet — like a shared work directory or contacts synced from your phone. When both sources are connected, Google Contacts results appear first, followed by email history.

### Google Contacts (optional)

To also search your Google Contacts, set up a Google Cloud project and authenticate goobook. This is a one-time setup:

#### 1. Create a Google Cloud project (or reuse an existing one)

Go to the [Google Cloud Console](https://console.cloud.google.com/) and create a new project (or select an existing one).

#### 2. Enable the People API

- In your project, go to **APIs & Services > Library**
- Search for **"People API"** (not "Contacts API") and click **Enable**

#### 3. Create OAuth credentials

- Go to **APIs & Services > Credentials**
- Click **+ Create Credentials > OAuth client ID**
- Select **Desktop application** as the application type
- Give it a name (e.g. "goobook")
- Save the **Client ID** and **Client Secret**

#### 4. Authenticate goobook

```bash
goobook authenticate -- YOUR_CLIENT_ID YOUR_CLIENT_SECRET
```

This opens a browser for Google OAuth consent. Once you authorize, goobook saves the token locally and caches your contacts (refreshes every 24 hours). You can force a cache refresh anytime with `goobook reload`.

### Adding contacts

Press `a` in the index or pager to add the sender of the current message to your Google Contacts (requires goobook authentication above).

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
