# g
GnuPG wrapper in bash using zenity and rofi/dmenu

# Config
Inside script you can set up some things.

# Usage
`g action`

where `action` is:  
`e` - encrypt message  
`d` - decrypt/verify message  
`s` - sign message  
`se` - sign & encrypt message  
`ef` - encrypt file  
`df` - decrypt/verify file  
`im` - import key  
`ex` - export key  
`gen` - generate new key  
`del` - delete key(s)  

Or simply run script to choose action

# Notes
Using 4096 RSA with no expire date for key generation.  
Expired and revoked uids are ignored. Use `--invalid` parameter with `del` or `ex` action to list those.  

# Dependencies
`bash`  
`zenity`  
optional `rofi` or `dmenu`  

Tested in Arch Linux and Tails
