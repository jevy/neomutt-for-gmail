# Neomutt for Gmail

A Nix flake providing Gmail-optimized configuration for neomutt, lieer, and notmuch. Get started with Gmail in neomutt with sensible defaults and Gmail-style keybindings.

## What This Provides

- **Gmail-optimized neomutt configuration** with virtual mailboxes, keybindings, and thread-based sorting
- **Lieer, notmuch, and msmtp** enabled by default
- **Virtual mailboxes** for Inbox, Unread, Starred, Sent, Drafts, and All Mail
- **Gmail-style keybindings** (S for spam, A for archive, I for inbox)
- **Vim keybindings** and sidebar navigation

## Quick Start

### 1. Add to your flake

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
          home.stateVersion = "23.11";
          
          programs.home-manager.enable = true;
          
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

### 2. Activate your configuration

```bash
home-manager switch --flake .#yourusername
```

### 3. Set up Gmail API credentials

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project
3. Enable the Gmail API
4. Create OAuth2 credentials (Desktop application)
5. Download the credentials JSON file

### 4. Initialize lieer

```bash
cd ~/Mail/gmail
gmi init your-email@gmail.com
gmi auth
gmi sync
```

### 5. Initialize notmuch

```bash
notmuch new
```

### 6. Launch neomutt

```bash
neomutt
```

## What's Configured

### Lieer
- Enabled by default
- Ignores lieer metadata files in notmuch

### Notmuch
- Enabled by default
- Configured to ignore `.json`, `.lock`, `.bak` files

### Neomutt
- **Virtual mailboxes** powered by notmuch:
  - Inbox (`tag:inbox`)
  - Unread (`tag:unread`)
  - Starred (`tag:starred`)
  - Sent (`tag:sent`)
  - Drafts (`tag:draft`)
  - All Mail (`*`)

- **Gmail-style keybindings**:
  - `S` - Mark as spam and remove from inbox
  - `A` - Archive (remove from inbox)
  - `I` - Move to inbox
  - `gi` - Go to inbox
  - `ga` - View entire thread
  - `\\` - Create virtual folder from query
  - `L` - Limit current view

- **Display settings**:
  - Thread-based sorting
  - Vim keybindings
  - Sidebar enabled (20 chars wide)
  - 10 lines of index in pager view

### MSMTP
- Enabled by default for sending mail

## Customization

You can override or extend any settings:

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

## Multiple Accounts

Add more Gmail accounts easily:

```nix
accounts.email.accounts = {
  personal = {
    address = "personal@gmail.com";
    primary = true;
    
  };
  
  work = {
    address = "work@gmail.com";
    
  };
};
```

## Troubleshooting

### Lieer authentication fails
Run `gmi auth` in your maildir (`~/Mail/gmail`) and ensure you have valid OAuth2 credentials.

### Notmuch doesn't find emails
Run `notmuch new` to reindex your mail database.

### Sync service not running
Check systemd status:
```bash
systemctl --user status lieer-gmail.service
systemctl --user status lieer-gmail.timer
```

## Why This Flake?

Home-manager already has modules for lieer, notmuch, and neomutt. This flake provides:

1. **Opinionated defaults** that work well together for Gmail
2. **Pre-configured virtual mailboxes** for common Gmail views
3. **Gmail-style keybindings** that feel familiar
4. **One-line import** instead of copying configuration

Think of it as a "batteries included" starting point that you can customize.

## Resources

- [Lieer Documentation](https://github.com/gauteh/lieer)
- [Notmuch Documentation](https://notmuchmail.org/)
- [Neomutt Documentation](https://neomutt.org/)
- [Home Manager Manual](https://nix-community.github.io/home-manager/)

## License

MIT